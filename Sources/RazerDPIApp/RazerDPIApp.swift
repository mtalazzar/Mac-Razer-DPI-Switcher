import AppKit
import RazerKit
import SwiftUI

@main
struct RazerDPIApp: App {
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
        if case .connected(_, let current, _) = model.status { return "\(current)" }
        return ""
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        switch model.status {
        case .searching:
            Text("Looking for the mouse…")
        case .disconnected:
            Text("Mouse not connected")
        case .connected(let name, let current, let saved):
            Text("\(name): \(current.description) DPI")
            Text("Saved in mouse (Windows): \(saved.description) DPI")
        case .failed(let message):
            Text("Error: \(message)")
        }

        Divider()

        ForEach(model.presets, id: \.self) { dpi in
            Toggle("\(dpi) DPI", isOn: Binding(
                get: { model.macDPI == dpi },
                set: { if $0 { model.choose(dpi) } }
            ))
        }

        Divider()

        Toggle("Apply When Mouse Connects", isOn: $model.autoApply)
        Button("Apply \(model.macDPI) DPI Now") { model.applyNow() }
        Button("Edit Presets…") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        Toggle("Open at Login", isOn: Binding(
            get: { model.launchAtLogin },
            set: { model.launchAtLogin = $0 }
        ))

        Divider()

        Button("Quit RazerDPI") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct PresetsView: View {
    @ObservedObject var model: AppModel
    @State private var text = ""
    @State private var message: String?

    var body: some View {
        Form {
            TextField("Mac DPI presets:", text: $text)
                .onSubmit(save)
            Text("Comma-separated, 200–6400 in steps of 100. Only the temporary DPI is changed; the DPI saved in the mouse for Windows is never modified.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { text = model.presets.map(String.init).joined(separator: ", ") }
    }

    private func save() {
        message = model.savePresets(from: text)
        if message == nil { text = model.presets.map(String.init).joined(separator: ", ") }
    }
}
