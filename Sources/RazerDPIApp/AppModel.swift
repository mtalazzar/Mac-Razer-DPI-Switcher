import AppKit
import Foundation
import RazerKit
import ServiceManagement

final class AppModel: ObservableObject {
    enum Status: Equatable {
        case searching
        case disconnected
        case connected(name: String, current: DPIValue, saved: DPIValue)
        case failed(String)
    }

    static let defaultPresets = [800, 1600]

    @Published private(set) var status: Status = .searching
    @Published private(set) var presets: [Int]
    /// The Mac DPI: applied when chosen and whenever the mouse connects.
    @Published private(set) var macDPI: Int
    @Published var autoApply: Bool {
        didSet { defaults.set(autoApply, forKey: Keys.autoApply) }
    }

    private enum Keys {
        static let presets = "presets", macDPI = "macDPI", autoApply = "autoApply"
    }

    private let defaults = UserDefaults.standard
    private let worker = DispatchQueue(label: "RazerDPI.worker")
    private var pending: DispatchWorkItem?
    private var monitor: DeviceMonitor?
    private var wakeObserver: NSObjectProtocol?

    init() {
        let stored = (defaults.array(forKey: Keys.presets) as? [Int]).flatMap(Self.validPresets)
        presets = stored ?? Self.defaultPresets
        macDPI = defaults.object(forKey: Keys.macDPI) as? Int ?? Self.defaultPresets[0]
        autoApply = defaults.object(forKey: Keys.autoApply) as? Bool ?? true
        if (try? Self.validationModel.validate(dpi: macDPI)) == nil { macDPI = presets[0] }

        monitor = DeviceMonitor { [weak self] in self?.refresh(after: 0.8) }
        monitor?.start()
        // USB devices can be reset across sleep; re-check on wake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh(after: 2.0) }
    }

    // MARK: Actions

    func choose(_ dpi: Int) {
        macDPI = dpi
        defaults.set(dpi, forKey: Keys.macDPI)
        refresh(after: 0, apply: true)
    }

    func applyNow() { refresh(after: 0, apply: true) }

    /// Returns an error message, or nil if saved.
    func savePresets(from text: String) -> String? {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
        let values = parts.compactMap(Int.init)
        guard !values.isEmpty, values.count == parts.count else { return "Enter numbers separated by commas, e.g. 800, 1600." }
        for v in values {
            do { try Self.validationModel.validate(dpi: v) } catch { return "\(error)" }
        }
        presets = Array(Set(values)).sorted()
        defaults.set(presets, forKey: Keys.presets)
        if !presets.contains(macDPI) { choose(presets[0]) }
        return nil
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }

    // MARK: Device sync

    private static var validationModel: RazerModel { DeviceCatalog.models[0] }

    private static func validPresets(_ values: [Int]) -> [Int]? {
        let ok = values.filter { (try? validationModel.validate(dpi: $0)) != nil }
        return ok.isEmpty ? nil : ok
    }

    /// Reads the mouse and, if `apply` (or auto-apply on connect), sets the Mac DPI.
    /// Bursts of plug events collapse into one run.
    private func refresh(after delay: TimeInterval, apply: Bool? = nil) {
        pending?.cancel()
        let target = (apply ?? autoApply) ? macDPI : nil
        let item = DispatchWorkItem { [weak self] in
            let status = Self.sync(target: target)
            DispatchQueue.main.async { self?.status = status }
        }
        pending = item
        worker.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Runs on the worker queue. A freshly plugged mouse can take a moment to
    /// answer, so a few attempts are made before giving up.
    private static func sync(target: Int?) -> Status {
        var lastError: Error?
        for attempt in 0..<4 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.5) }
            guard let mouse = RazerMouse.connected().first else {
                lastError = nil
                continue
            }
            do {
                var current = try mouse.getDPI(.temporary)
                if let target, current != DPIValue(x: UInt16(target), y: UInt16(target)) {
                    // Temporary storage only: the saved (Windows) DPI is never written.
                    current = try mouse.setDPI(target, storage: .temporary)
                }
                return .connected(name: mouse.model.name, current: current, saved: try mouse.getDPI(.saved))
            } catch {
                lastError = error
            }
        }
        return lastError.map { .failed("\($0)") } ?? .disconnected
    }
}
