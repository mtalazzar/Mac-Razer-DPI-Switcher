// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import RazerKit
import ServiceManagement

final class AppModel: ObservableObject {
    struct MouseState: Identifiable, Equatable {
        let device: DetectedDevice
        let model: RazerModel
        var current: DPIValue?
        /// DPI saved in the mouse (what other computers see), when readable.
        var saved: DPIValue?
        var error: String?
        var id: UInt32 { device.id }
    }

    /// What a sync run may write.
    enum Apply {
        case none
        /// Mac DPI for every confirmed mouse (on connect, if auto-apply is on).
        case automatic
        /// Mac DPI for one family (the user chose a preset or "Apply Now").
        case family(String)
        /// A specific value for one family (restore original).
        case value(String, Int)
    }

    @Published private(set) var mice: [MouseState] = []
    /// Razer mice that aren't supported (excluded or not in the catalog).
    @Published private(set) var others: [DetectedDevice] = []
    @Published private(set) var hasScanned = false
    @Published var autoApply: Bool {
        didSet { UserDefaults.standard.set(autoApply, forKey: "autoApply") }
    }

    let settings = FamilySettings()
    private let worker = DispatchQueue(label: "DPISwitcher.worker")
    /// Only plug/wake events are debounced (a burst becomes one run). User
    /// actions are never cancelled; the serial worker runs everything in order.
    private var pendingAutomatic: DispatchWorkItem?
    private var monitor: DeviceMonitor?
    private var wakeObserver: NSObjectProtocol?

    init() {
        autoApply = UserDefaults.standard.object(forKey: "autoApply") as? Bool ?? true
        monitor = DeviceMonitor { [weak self] in self?.sync(after: 0.8, apply: .automatic) }
        monitor?.start()
        // USB devices can be reset across sleep; re-check on wake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.sync(after: 2.0, apply: .automatic) }
    }

    // MARK: Actions

    func choose(_ dpi: Int, for mouse: MouseState) {
        guard confirmIfNeeded(mouse.model) else { return }
        settings.setMacDPI(dpi, for: mouse.model)
        objectWillChange.send()
        sync(after: 0, apply: .family(mouse.model.family))
    }

    func applyNow(_ mouse: MouseState) {
        guard confirmIfNeeded(mouse.model) else { return }
        sync(after: 0, apply: .family(mouse.model.family))
    }

    func restoreOriginal(_ mouse: MouseState) {
        guard let original = settings.originalDPI(for: mouse.model) else { return }
        sync(after: 0, apply: .value(mouse.model.family, original))
    }

    func rescan() { sync(after: 0, apply: .none) }

    /// Returns an error message, or nil if saved.
    func savePresets(_ text: String, for model: RazerModel) -> String? {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        let values = parts.compactMap(Int.init)
        guard !values.isEmpty, values.count == parts.count else { return "Enter numbers separated by commas, e.g. 800, 1600." }
        for v in values {
            do { try model.validate(dpi: v) } catch { return "\(error)" }
        }
        let presets = Array(Set(values)).sorted()
        settings.setPresets(presets, for: model)
        if !presets.contains(settings.macDPI(for: model)) { settings.setMacDPI(presets[0], for: model) }
        objectWillChange.send()
        return nil
    }

    /// Copies a diagnostic report and opens a pre-filled GitHub issue.
    func report(_ device: DetectedDevice) {
        worker.async {
            let text = Diagnostics.report(for: device)
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                if let url = ProjectInfo.reportURL(for: device, result: text) { NSWorkspace.shared.open(url) }
            }
        }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }

    /// Shows the model's cautions once; returns true if the user accepts.
    private func confirmIfNeeded(_ model: RazerModel) -> Bool {
        if settings.isConfirmed(model) { return true }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Change the DPI of your \(model.name)?"
        alert.informativeText = model.cautions.joined(separator: "\n\n")
        alert.alertStyle = model.keepsOtherComputersDPI ? .informational : .warning
        alert.addButton(withTitle: "Change DPI")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        settings.setConfirmed(model)
        return true
    }

    // MARK: Device sync

    /// Rescans and (depending on `apply`) writes DPI on the worker queue.
    private func sync(after delay: TimeInterval, apply: Apply) {
        var effective = apply
        let isAutomatic: Bool
        if case .automatic = apply {
            isAutomatic = true
            if !autoApply { effective = .none }
        } else {
            isAutomatic = false
        }

        let settings = self.settings
        let item = DispatchWorkItem { [weak self] in
            let (mice, others) = Self.sync(apply: effective, settings: settings)
            DispatchQueue.main.async {
                self?.mice = mice
                self?.others = others
                self?.hasScanned = true
            }
        }
        if isAutomatic {
            pendingAutomatic?.cancel()
            pendingAutomatic = item
        }
        worker.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private static func sync(apply: Apply, settings: FamilySettings) -> ([MouseState], [DetectedDevice]) {
        let devices = DeviceScanner.scan()
        let others = devices.filter { $0.model == nil && ($0.looksLikeMouse || $0.exclusion != nil) }
        let mice = devices.compactMap(RazerMouse.init).map { sync($0, apply: apply, settings: settings) }
        return (mice, others)
    }

    /// A freshly plugged mouse can take a moment to answer, so a few attempts are made.
    private static func sync(_ mouse: RazerMouse, apply: Apply, settings: FamilySettings) -> MouseState {
        let model = mouse.model
        let target: Int?
        switch apply {
        case .none: target = nil
        case .automatic: target = settings.isConfirmed(model) ? settings.macDPI(for: model) : nil
        case .family(let f): target = f == model.family ? settings.macDPI(for: model) : nil
        case .value(let f, let dpi): target = f == model.family ? dpi : nil
        }

        var state = MouseState(device: mouse.device, model: model)
        for attempt in 0..<4 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.5) }
            do {
                var current = try mouse.currentDPI()
                if let target, current != DPIValue(x: UInt16(target), y: UInt16(target)) {
                    if model.writeStorage == .saved, settings.originalDPI(for: model) == nil {
                        settings.setOriginalDPI(Int(current.x), for: model)
                    }
                    current = try mouse.setDPI(target)
                }
                state.current = current
                state.saved = mouse.savedDPI()
                state.error = nil
                return state
            } catch RazerError.invalidDPI(let why) {
                state.error = "Invalid DPI: \(why)."
                return state
            } catch {
                state.error = "\(error)"
            }
        }
        return state
    }
}
