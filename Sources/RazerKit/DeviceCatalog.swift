import Foundation

public struct RazerModel: Equatable {
    public let productID: Int
    public let name: String
    public let dpiRange: ClosedRange<Int>
    /// DPI values must be a multiple of this.
    public let dpiStep: Int
    /// Transaction id the firmware answers to. nil means "not confirmed on real
    /// hardware yet": reads may probe for it, writes are refused.
    public let transactionID: UInt8?

    public func validate(dpi: Int) throws {
        guard dpiRange.contains(dpi) else {
            throw RazerError.invalidDPI("\(dpi) is outside \(dpiRange.lowerBound)–\(dpiRange.upperBound)")
        }
        guard dpi % dpiStep == 0 else {
            throw RazerError.invalidDPI("\(dpi) must be a multiple of \(dpiStep)")
        }
    }
}

public enum DeviceCatalog {
    public static let razerVendorID = 0x1532

    /// Only models listed here are ever written to.
    public static let models: [RazerModel] = [
        // Transaction id 0xFF: answered on real hardware (firmware 2.00) and is
        // what OpenRazer's razer_attr_write_dpi / read_dpi use for this pid.
        RazerModel(productID: 0x006E, name: "Razer DeathAdder Essential",
                   dpiRange: 200...6400, dpiStep: 100, transactionID: 0xFF),
    ]

    public static func model(productID: Int) -> RazerModel? {
        models.first { $0.productID == productID }
    }

    /// Transaction ids used across Razer firmware generations (OpenRazer).
    static let candidateTransactionIDs: [UInt8] = [0x3F, 0x1F, 0xFF]
}
