import Foundation
import IOKit
import IOKit.hid
import CRazerUSB

public enum RazerError: Error, CustomStringConvertible {
    case noDevice
    case notPermitted
    case openFailed(IOReturn)
    case ioFailed(String, IOReturn)
    case noResponse
    case deviceStatus(UInt8)
    case invalidDPI(String)
    case unconfirmedModel(String)
    case readbackMismatch(expected: DPIValue, got: DPIValue)

    public var description: String {
        switch self {
        case .noDevice:
            return "No supported Razer mouse is connected."
        case .notPermitted:
            return "macOS blocked access to the mouse. Allow this app under System Settings → Privacy & Security → Input Monitoring, then try again."
        case .openFailed(let r):
            return "Could not open the mouse (IOReturn 0x\(String(UInt32(bitPattern: r), radix: 16)))."
        case .ioFailed(let what, let r):
            return "\(what) failed (IOReturn 0x\(String(UInt32(bitPattern: r), radix: 16)))."
        case .noResponse:
            return "The mouse did not answer."
        case .deviceStatus(let s):
            let name = RazerReport.Status(rawValue: s).map { "\($0)" } ?? "unknown"
            return "The mouse rejected the command (status 0x\(String(s, radix: 16)): \(name))."
        case .invalidDPI(let why):
            return "Invalid DPI: \(why)."
        case .unconfirmedModel(let name):
            return "\(name) has not been verified for writing yet; refusing to change its settings."
        case .readbackMismatch(let expected, let got):
            return "The mouse reports \(got) DPI after setting \(expected)."
        }
    }
}

/// One connected Razer mouse, addressed through its HID mouse interface
/// (the only interface whose descriptor declares the 90-byte feature report).
public final class RazerMouse {
    public let model: RazerModel
    public let locationID: Int
    public let firmware: String
    let device: IOHIDDevice
    private let lock = NSLock()

    init(device: IOHIDDevice, model: RazerModel) {
        self.device = device
        self.model = model
        self.locationID = Self.intProperty(device, kIOHIDLocationIDKey) ?? 0
        let version = Self.intProperty(device, kIOHIDVersionNumberKey) ?? 0
        self.firmware = "\(version >> 8).\(String(format: "%02x", version & 0xFF))"
    }

    // MARK: Discovery

    /// Matching dictionary for the HID interfaces we talk to.
    static var matching: [String: Any] {
        [
            kIOHIDVendorIDKey: DeviceCatalog.razerVendorID,
            kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDPrimaryUsageKey: kHIDUsage_GD_Mouse,
        ]
    }

    /// Wraps `device` if it is a supported model's control interface.
    static func make(_ device: IOHIDDevice) -> RazerMouse? {
        guard let pid = intProperty(device, kIOHIDProductIDKey),
              let model = DeviceCatalog.model(productID: pid),
              (intProperty(device, kIOHIDMaxFeatureReportSizeKey) ?? 0) >= RazerReport.size
        else { return nil }
        return RazerMouse(device: device, model: model)
    }

    /// Currently connected supported mice.
    public static func connected() -> [RazerMouse] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return set.compactMap(make).sorted { $0.locationID < $1.locationID }
    }

    static func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
        IOHIDDeviceGetProperty(device, key as CFString) as? Int
    }

    // MARK: Transport

    /// USB interface (wIndex) that carries the Razer control report on mice.
    static let controlInterface: UInt16 = 0

    /// Sends one command and returns the device's matching, successful answer.
    ///
    /// The report goes out as a HID class control request on the device's
    /// control pipe (see CRazerUSB). The HID interfaces are never opened, so no
    /// Input Monitoring permission is needed and the cursor is never interrupted.
    func send(_ command: RazerCommand, transactionID: UInt8) throws -> RazerReport {
        lock.lock()
        defer { lock.unlock() }

        let location = UInt32(truncatingIfNeeded: locationID)
        let request = command.report(transactionID: transactionID).encoded()
        let setResult = request.withUnsafeBufferPointer {
            razer_usb_set_feature(location, Self.controlInterface, $0.baseAddress!, UInt16($0.count))
        }
        if setResult == kIOReturnNoDevice { throw RazerError.noDevice }
        guard setResult == kIOReturnSuccess else { throw RazerError.ioFailed("Sending to the mouse", setResult) }

        // The firmware needs a moment to process; it answers "busy" until done.
        for attempt in 0..<12 {
            usleep(attempt == 0 ? 2_000 : 8_000)
            var buffer = [UInt8](repeating: 0, count: RazerReport.size)
            var length = UInt16(buffer.count)
            let getResult = buffer.withUnsafeMutableBufferPointer {
                razer_usb_get_feature(location, Self.controlInterface, $0.baseAddress!, &length)
            }
            guard getResult == kIOReturnSuccess else { throw RazerError.ioFailed("Reading from the mouse", getResult) }
            guard length == RazerReport.size, let response = RazerReport(bytes: buffer) else { continue }

            switch response.parsedStatus {
            case .busy, .new:
                continue
            case .success where command.matches(response, transactionID: transactionID):
                return response
            case .success:
                continue // a stale answer to something else
            default:
                throw RazerError.deviceStatus(response.status)
            }
        }
        throw RazerError.noResponse
    }

    // MARK: DPI

    /// Read-only. Tries each known transaction id and reports what the mouse
    /// answered, so the right one can be confirmed before anything is written.
    public func probe() -> [(transactionID: UInt8, result: Result<DPIValue, Error>)] {
        DeviceCatalog.candidateTransactionIDs.map { id in
            (id, Result { try readDPI(.temporary, transactionID: id) })
        }
    }

    public func getDPI(_ storage: DPIStorage = .temporary) throws -> DPIValue {
        if let id = model.transactionID { return try readDPI(storage, transactionID: id) }
        // Unconfirmed model: reads are harmless, so find an id that answers.
        var lastError: Error = RazerError.noResponse
        for id in DeviceCatalog.candidateTransactionIDs {
            do { return try readDPI(storage, transactionID: id) } catch { lastError = error }
        }
        throw lastError
    }

    /// Sets the DPI and reads it back to confirm the mouse applied it.
    @discardableResult
    public func setDPI(_ dpi: Int, storage: DPIStorage = .temporary) throws -> DPIValue {
        guard let id = model.transactionID else { throw RazerError.unconfirmedModel(model.name) }
        try model.validate(dpi: dpi)
        let value = DPIValue(x: UInt16(dpi), y: UInt16(dpi))
        _ = try send(.setDPI(storage, x: value.x, y: value.y), transactionID: id)
        let readBack = try readDPI(storage, transactionID: id)
        guard readBack == value else { throw RazerError.readbackMismatch(expected: value, got: readBack) }
        return readBack
    }

    private func readDPI(_ storage: DPIStorage, transactionID: UInt8) throws -> DPIValue {
        let response = try send(.getDPI(storage), transactionID: transactionID)
        guard let value = DPIValue(response: response) else { throw RazerError.noResponse }
        return value
    }
}
