// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import RazerKit
import SwiftUI

@main
struct DPISwitcherApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Menu bar only, no Dock icon (also set via LSUIElement in the bundle).
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: "computermouse")
            Text(menuBarTitle)
        }

        Settings {
            PresetsView(model: model)
        }
    }

    private var menuBarTitle: String {
        model.mice.first?.current.map(\.description) ?? ""
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if !model.hasScanned {
            Text("Looking for mice…")
        } else if model.mice.isEmpty && model.others.isEmpty {
            Text("No Razer mouse connected")
        }

        ForEach(model.mice) { mouse in
            MouseSection(model: model, mouse: mouse)
            Divider()
        }

        if !model.others.isEmpty {
            ForEach(model.others) { device in
                Menu("\(device.displayName): not supported") {
                    if let exclusion = device.exclusion {
                        Text(exclusion.reason.prefix(1).uppercased() + exclusion.reason.dropFirst())
                    } else {
                        Text("This mouse isn't in the model list yet.")
                        Button("Report This Mouse on GitHub…") { model.report(device) }
                    }
                }
            }
            Divider()
        }

        Toggle("Apply When Mouse Connects", isOn: $model.autoApply)
        Button("Edit Presets…") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        Toggle("Open at Login", isOn: Binding(
            get: { model.launchAtLogin },
            set: { model.launchAtLogin = $0 }
        ))
        Button("Refresh") { model.rescan() }

        Divider()

        Button("About \(ProjectInfo.name) \(ProjectInfo.version)…") {
            if let url = URL(string: ProjectInfo.repository) { NSWorkspace.shared.open(url) }
        }
        Button("Quit \(ProjectInfo.name)") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct MouseSection: View {
    @ObservedObject var model: AppModel
    let mouse: AppModel.MouseState

    private var settings: FamilySettings { model.settings }

    var body: some View {
        if let current = mouse.current {
            Text("\(mouse.model.name): \(current.description) DPI")
        } else {
            Text(mouse.model.name)
        }
        if let error = mouse.error {
            Text(error)
        }
        if let saved = mouse.saved {
            Text("Saved in mouse (other computers): \(saved.description) DPI")
        }
        if mouse.model.support == .untested {
            Text("Untested model")
        }
        if mouse.model.batteryPowered {
            Text("Wireless: DPI stays until the mouse powers off")
        }
        if mouse.model.writeStorage == .saved {
            Text("Changes the DPI on all computers")
        }
        if !settings.isConfirmed(mouse.model) {
            Text("Choose a DPI to start using this mouse")
        }

        ForEach(settings.presets(for: mouse.model), id: \.self) { dpi in
            Toggle("\(dpi) DPI", isOn: Binding(
                get: { settings.isConfirmed(mouse.model) && settings.macDPI(for: mouse.model) == dpi },
                set: { if $0 { model.choose(dpi, for: mouse) } }
            ))
        }

        if mouse.error != nil {
            Button("Try Again") { model.applyNow(mouse) }
        }
        if mouse.model.writeStorage == .saved, let original = settings.originalDPI(for: mouse.model) {
            Button("Restore Original DPI (\(original))") { model.restoreOriginal(mouse) }
        }
        if mouse.model.support == .untested {
            Button("Report How It Works on GitHub…") { model.report(mouse.device) }
        }
    }
}

struct PresetsView: View {
    @ObservedObject var model: AppModel

    /// One row per family, even with two of the same mouse connected.
    private var families: [RazerModel] {
        var seen = Set<String>()
        return model.mice.map(\.model).filter { seen.insert($0.family).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.mice.isEmpty {
                Text("Connect a supported Razer mouse to edit its presets.")
                    .foregroundStyle(.secondary)
            }
            ForEach(families, id: \.family) { razerModel in
                FamilyPresetsRow(model: model, razerModel: razerModel)
            }
            Text("DPI is set on this Mac only. For wired mice it's temporary: the DPI saved in the mouse for your other computers is never changed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 420)
    }
}

struct FamilyPresetsRow: View {
    @ObservedObject var model: AppModel
    let razerModel: RazerModel
    @State private var text = ""
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(razerModel.family).font(.headline)
            HStack {
                TextField("Presets", text: $text).onSubmit(save)
                Button("Save", action: save)
            }
            Text("Comma-separated, \(RazerModel.minDPI)–\(razerModel.maxDPI) in steps of \(RazerModel.dpiStep).")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let message {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        text = model.settings.presets(for: razerModel).map(String.init).joined(separator: ", ")
    }

    private func save() {
        message = model.savePresets(text, for: razerModel)
        if message == nil { load() }
    }
}
