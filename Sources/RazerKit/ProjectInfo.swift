// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public enum ProjectInfo {
    public static let name = "DPI Switcher"
    public static let version = "1.0.0"
    /// Set this to the GitHub repository before publishing.
    public static let repository = "https://github.com/OWNER/dpi-switcher"

    /// Pre-filled "Report your mouse" issue (fields match .github/ISSUE_TEMPLATE/mouse-report.yml).
    public static func reportURL(for device: DetectedDevice, result: String) -> URL? {
        var components = URLComponents(string: repository + "/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "template", value: "mouse-report.yml"),
            URLQueryItem(name: "title", value: "Mouse report: \(device.displayName) (\(device.usbID))"),
            URLQueryItem(name: "usb-id", value: device.usbID),
            URLQueryItem(name: "model", value: device.displayName),
            URLQueryItem(name: "firmware", value: device.firmware),
            URLQueryItem(name: "macos", value: Diagnostics.macOSDescription),
            URLQueryItem(name: "details", value: result),
        ]
        return components?.url
    }
}

public enum Diagnostics {
    public static var macOSDescription: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        var arch = "x86_64"
        #if arch(arm64)
        arch = "arm64"
        #endif
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion) (\(arch))"
    }

    /// Plain-text summary for bug reports. Only reads from the mouse.
    public static func report(for device: DetectedDevice) -> String {
        var lines = [
            "\(ProjectInfo.name) \(ProjectInfo.version), OpenRazer data \(DeviceCatalog.openRazerCommit.prefix(12))",
            "macOS \(macOSDescription)",
            "Device: \(device.displayName) [\(device.usbID)] firmware \(device.firmware), USB name \"\(device.usbName)\"",
        ]
        if let model = device.model {
            lines.append("Catalog: \(model.support.rawValue), tid 0x\(String(format: "%02X", model.transactionID)), interface \(model.interface), write \(model.writeStorage), read \(model.readStorage), max \(model.maxDPI)")
            if let mouse = RazerMouse(device) {
                lines.append("Current DPI: " + describe(Result { try mouse.currentDPI() }))
                if model.writeStorage == .temporary {
                    lines.append("Saved DPI: " + (mouse.savedDPI().map { "\($0)" } ?? "unreadable"))
                }
            }
        } else if let exclusion = device.exclusion {
            lines.append("Not supported: \(exclusion.reason)")
        } else {
            lines.append("Not in the catalog. Read-only probe:")
            for p in Probe.run(device) {
                lines.append("  interface \(p.interface) tid 0x\(String(format: "%02X", p.transactionID)): " + describe(p.result))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func describe(_ result: Result<DPIValue, Error>) -> String {
        switch result {
        case .success(let dpi): return "\(dpi)"
        case .failure(let error): return "error: \(error)"
        }
    }
}
