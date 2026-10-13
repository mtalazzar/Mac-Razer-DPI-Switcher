// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import RazerKit

let usage = """
usage: dpiswitcher <command> [options]

  list [--all]           connected Razer mice (--all: every Razer USB device)
  get                    current DPI (and the DPI saved in the mouse)
  set <dpi> [--yes]      set the DPI; --yes is required for models that are
                         untested, wireless, or only take a saved DPI
  report                 details to paste into a GitHub issue (read-only)
  models                 every supported model

options:
  -d, --device <n>       pick a mouse by its number from `list` (default: 1)
"""

struct Options {
    var command: String?
    var arguments: [String] = []
    var device = 1
    var all = false
    var yes = false
}

func parse(_ args: [String]) throws -> Options {
    var options = Options()
    var rest = args[...]
    while let arg = rest.popFirst() {
        switch arg {
        case "-d", "--device":
            guard let value = rest.popFirst().flatMap(Int.init), value > 0 else { throw UsageError() }
            options.device = value
        case "--all": options.all = true
        case "--yes", "-y": options.yes = true
        case "-h", "--help": options.command = nil; return options
        default:
            if options.command == nil { options.command = arg } else { options.arguments.append(arg) }
        }
    }
    return options
}

struct UsageError: Error {}

func listed(all: Bool) -> [DetectedDevice] {
    DeviceScanner.scan().filter { all || $0.looksLikeMouse || $0.model != nil }
}

func selected(_ options: Options) throws -> DetectedDevice {
    let devices = listed(all: false)
    guard !devices.isEmpty else { throw RazerError.noDevice }
    guard options.device <= devices.count else {
        throw RazerError.unsupported("There is no mouse #\(options.device); run `dpiswitcher list`.")
    }
    return devices[options.device - 1]
}

func supported(_ device: DetectedDevice) throws -> RazerMouse {
    if let mouse = RazerMouse(device) { return mouse }
    if let exclusion = device.exclusion {
        throw RazerError.unsupported("\(exclusion.name) is not supported: \(exclusion.reason).")
    }
    throw RazerError.unsupported("\(device.displayName) [\(device.usbID)] isn't in the model list yet. Run `dpiswitcher report` and open an issue at \(ProjectInfo.repository).")
}

func status(of device: DetectedDevice) -> String {
    if let model = device.model { return model.support == .verified ? "verified" : "untested" }
    return device.exclusion != nil ? "not supported" : "unknown"
}

func run(_ options: Options) throws {
    switch options.command {
    case "list":
        let devices = listed(all: options.all)
        if devices.isEmpty { print("No Razer mouse connected.") }
        for (i, d) in devices.enumerated() {
            print("\(i + 1). \(d.displayName)  [\(d.usbID)]  firmware \(d.firmware)  (\(status(of: d)))")
        }

    case "get":
        let mouse = try supported(try selected(options))
        print("\(mouse.model.name)")
        print("current: \(try mouse.currentDPI()) DPI")
        if let saved = mouse.savedDPI() { print("saved:   \(saved) DPI") }

    case "set":
        guard options.arguments.count == 1, let dpi = Int(options.arguments[0]) else { throw UsageError() }
        let mouse = try supported(try selected(options))
        try mouse.model.validate(dpi: dpi)
        if mouse.model.needsConfirmation && !options.yes {
            print("\(mouse.model.name):")
            mouse.model.cautions.forEach { print("  - \($0)") }
            print("Run again with --yes to continue.")
            exit(3)
        }
        let applied = try mouse.setDPI(dpi)
        print("\(mouse.model.name): \(applied) DPI")
        if let saved = mouse.savedDPI() { print("saved in the mouse: \(saved) DPI (unchanged)") }

    case "report":
        print(Diagnostics.report(for: try selected(options)))

    case "models":
        for m in DeviceCatalog.models.sorted(by: { $0.name < $1.name }) {
            var notes = [m.support.rawValue, "max \(m.maxDPI)"]
            if m.batteryPowered { notes.append("wireless") }
            if m.writeStorage == .saved { notes.append("saved DPI only") }
            print(String(format: "1532:%04X  ", m.productID) + "\(m.name)  (\(notes.joined(separator: ", ")))")
        }

    default:
        print(usage)
        exit(options.command == nil ? 0 : 2)
    }
}

do {
    try run(try parse(Array(CommandLine.arguments.dropFirst())))
} catch is UsageError {
    print(usage)
    exit(2)
} catch {
    FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
