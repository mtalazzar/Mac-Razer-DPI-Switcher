import Foundation

/// The 90-byte Razer feature report, laid out as documented by OpenRazer
/// (driver/razercommon.h):
///
///     [0]      status
///     [1]      transaction id
///     [2..3]   remaining packets (big endian)
///     [4]      protocol type (always 0)
///     [5]      data size (number of meaningful argument bytes)
///     [6]      command class
///     [7]      command id
///     [8..87]  arguments (80 bytes)
///     [88]     crc  = XOR of bytes 2..87
///     [89]     reserved (0)
public struct RazerReport: Equatable {
    public static let size = 90
    public static let argumentCount = 80

    public enum Status: UInt8 {
        case new = 0x00
        case busy = 0x01
        case success = 0x02
        case failure = 0x03
        case timeout = 0x04
        case notSupported = 0x05
    }

    public var status: UInt8
    public var transactionID: UInt8
    public var remainingPackets: UInt16
    public var protocolType: UInt8
    public var dataSize: UInt8
    public var commandClass: UInt8
    public var commandID: UInt8
    public var arguments: [UInt8]

    init(transactionID: UInt8, dataSize: UInt8, commandClass: UInt8, commandID: UInt8, arguments: [UInt8]) {
        precondition(arguments.count <= Self.argumentCount)
        self.status = Status.new.rawValue
        self.transactionID = transactionID
        self.remainingPackets = 0
        self.protocolType = 0
        self.dataSize = dataSize
        self.commandClass = commandClass
        self.commandID = commandID
        self.arguments = arguments + Array(repeating: 0, count: Self.argumentCount - arguments.count)
    }

    /// Parses a report received from the device. Returns nil if the length is wrong.
    public init?(bytes: [UInt8]) {
        guard bytes.count == Self.size else { return nil }
        status = bytes[0]
        transactionID = bytes[1]
        remainingPackets = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        protocolType = bytes[4]
        dataSize = bytes[5]
        commandClass = bytes[6]
        commandID = bytes[7]
        arguments = Array(bytes[8..<88])
    }

    public var parsedStatus: Status? { Status(rawValue: status) }

    public func encoded() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Self.size)
        bytes[0] = status
        bytes[1] = transactionID
        bytes[2] = UInt8(remainingPackets >> 8)
        bytes[3] = UInt8(remainingPackets & 0xFF)
        bytes[4] = protocolType
        bytes[5] = dataSize
        bytes[6] = commandClass
        bytes[7] = commandID
        bytes.replaceSubrange(8..<88, with: arguments)
        bytes[88] = Self.crc(bytes)
        bytes[89] = 0
        return bytes
    }

    public static func crc(_ bytes: [UInt8]) -> UInt8 {
        bytes[2..<88].reduce(0, ^)
    }
}

/// Where the mouse keeps a DPI value.
public enum DPIStorage: UInt8, CustomStringConvertible {
    /// Active until the mouse loses power (unplugged). Never touches the saved value.
    case temporary = 0x00 // OpenRazer: NOSTORE
    /// Written to the mouse's memory; survives unplugging. This is what Windows sees.
    case saved = 0x01 // OpenRazer: VARSTORE

    public var description: String { self == .temporary ? "temporary" : "saved" }
}

/// The complete set of commands this project is able to send.
///
/// This is deliberately an allowlist: there is no way to build a report for any
/// other command class (firmware, flash, device mode, etc.), so nothing outside
/// reading and setting DPI can ever reach the mouse.
public enum RazerCommand: Equatable {
    case getDPI(DPIStorage)
    case setDPI(DPIStorage, x: UInt16, y: UInt16)

    static let dpiClass: UInt8 = 0x04
    static let setDPIID: UInt8 = 0x05
    static let getDPIID: UInt8 = 0x85

    public var isWrite: Bool {
        if case .setDPI = self { return true }
        return false
    }

    public func report(transactionID: UInt8) -> RazerReport {
        switch self {
        case .getDPI(let storage):
            return RazerReport(transactionID: transactionID, dataSize: 0x07,
                               commandClass: Self.dpiClass, commandID: Self.getDPIID,
                               arguments: [storage.rawValue])
        case .setDPI(let storage, let x, let y):
            return RazerReport(transactionID: transactionID, dataSize: 0x07,
                               commandClass: Self.dpiClass, commandID: Self.setDPIID,
                               arguments: [storage.rawValue,
                                           UInt8(x >> 8), UInt8(x & 0xFF),
                                           UInt8(y >> 8), UInt8(y & 0xFF),
                                           0x00, 0x00])
        }
    }

    /// True if `response` is the device's answer to this command.
    func matches(_ response: RazerReport, transactionID: UInt8) -> Bool {
        let sent = report(transactionID: transactionID)
        return response.transactionID == transactionID
            && response.commandClass == sent.commandClass
            && response.commandID == sent.commandID
    }
}

public struct DPIValue: Equatable, CustomStringConvertible {
    public let x: UInt16
    public let y: UInt16
    public var description: String { x == y ? "\(x)" : "\(x)x\(y)" }

    /// Decodes the DPI from a successful get-DPI response.
    init?(response: RazerReport) {
        guard response.commandClass == RazerCommand.dpiClass,
              response.commandID == RazerCommand.getDPIID else { return nil }
        let a = response.arguments
        x = UInt16(a[1]) << 8 | UInt16(a[2])
        y = UInt16(a[3]) << 8 | UInt16(a[4])
    }

    public init(x: UInt16, y: UInt16) {
        self.x = x
        self.y = y
    }
}
