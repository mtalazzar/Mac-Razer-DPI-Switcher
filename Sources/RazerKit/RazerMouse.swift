// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import IOKit

public enum RazerError: Error, CustomStringConvertible {
    case noDevice
    case unsupported(String)
    case ioFailed(String, IOReturn)
    case noResponse
    case notResponding
    case deviceStatus(UInt8)
    case invalidDPI(String)
    case readbackMismatch(expected: DPIValue, got: DPIValue)

    public var description: String {
        switch self {
        case .noDevice:
            return "No supported Razer mouse is connected."
        case .unsupported(let why):
            return why
        case .ioFailed(let what, let r):
            return "\(what) failed (IOReturn 0x\(String(UInt32(bitPattern: r), radix: 16)))."
        case .noResponse:
            return "The mouse did not answer."
        case .notResponding:
            return "The mouse isn't responding. If it's wireless, check that it's switched on and awake."
        case .deviceStatus(let s):
            let name = RazerReport.Status(rawValue: s).map { "\($0)" } ?? "unknown"
            return "The mouse rejected the command (status 0x\(String(s, radix: 16)): \(name))."
        case .invalidDPI(let why):
            return "Invalid DPI: \(why)."
        case .readbackMismatch(let expected, let got):
            return "The mouse reports \(got) DPI after setting \(expected)."
        }
    }
}

/// A connected mouse whose model is in the catalog.
public final class RazerMouse {
    public let device: DetectedDevice
    public let model: RazerModel

    public init?(_ device: DetectedDevice) {
        guard let model = device.model else { return nil }
        self.device = device
        self.model = model
    }

    /// Currently connected supported mice, ordered by port.
    public static func connected() -> [RazerMouse] {
        DeviceScanner.scan().compactMap(RazerMouse.init)
    }

    /// The DPI the mouse is using now.
    public func currentDPI() throws -> DPIValue {
        try read(model.readStorage)
    }

    /// The DPI saved in the mouse, i.e. what other computers see. Only
    /// meaningful for models that take temporary writes; nil if unreadable.
    public func savedDPI() -> DPIValue? {
        guard model.writeStorage == .temporary else { return nil }
        return try? read(.saved)
    }

    /// Sets the DPI using the model's storage and reads it back to confirm it.
    @discardableResult
    public func setDPI(_ dpi: Int) throws -> DPIValue {
        try model.validate(dpi: dpi)
        let before = try? currentDPI()
        let value = DPIValue(x: UInt16(dpi), y: UInt16(dpi))
        _ = try send(.setDPI(model.writeStorage, x: value.x, y: value.y))
        let readBack = try currentDPI()
        guard readBack == value else {
            // The firmware picked something else; put back what it had before.
            if let before { _ = try? send(.setDPI(model.writeStorage, x: before.x, y: before.y)) }
            throw RazerError.readbackMismatch(expected: value, got: readBack)
        }
        return readBack
    }

    private func read(_ storage: DPIStorage) throws -> DPIValue {
        guard let value = DPIValue(response: try send(.getDPI(storage))) else { throw RazerError.noResponse }
        return value
    }

    private func send(_ command: RazerCommand) throws -> RazerReport {
        try Transport.send(command, location: device.locationID, interface: model.interface,
                           transactionID: model.transactionID, responseDelay: model.responseDelay)
    }
}

public struct ProbeResult {
    public let transactionID: UInt8
    public let interface: UInt16
    public let result: Result<DPIValue, Error>
}

public enum Probe {
    /// Read-only: asks the device for its DPI with each known protocol variant.
    /// Used to report unknown models; never writes anything.
    public static func run(_ device: DetectedDevice) -> [ProbeResult] {
        var results: [ProbeResult] = []
        for interface in DeviceCatalog.candidateInterfaces {
            for id in DeviceCatalog.candidateTransactionIDs {
                let result = Result {
                    let response = try Transport.send(.getDPI(.temporary), location: device.locationID,
                                                      interface: interface, transactionID: id,
                                                      responseDelay: 60_000)
                    guard let value = DPIValue(response: response) else { throw RazerError.noResponse }
                    return value
                }
                results.append(ProbeResult(transactionID: id, interface: interface, result: result))
            }
        }
        return results
    }
}
