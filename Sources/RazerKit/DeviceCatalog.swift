// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

public struct RazerModel: Equatable {
    public enum Support: String {
        /// Tested on real hardware with this project (data/verified-models.json).
        case verified
        /// Protocol data from OpenRazer, not yet confirmed on macOS.
        case untested
    }

    /// A conservative floor for every model: the DeathAdder Essential (firmware
    /// 2.00) answers 100 or 150 by jumping to 1800 DPI, and 200 works on it.
    public static let minDPI = 200
    public static let dpiStep = 50

    public let productID: Int
    public let name: String
    /// Name shared by the wired / wireless / receiver ids of one mouse; settings are kept per family.
    public let family: String
    public let maxDPI: Int
    /// Transaction id the firmware answers to.
    public let transactionID: UInt8
    /// Where set-DPI writes. `.saved` means the value is also seen on other computers.
    public let writeStorage: DPIStorage
    /// Storage the driver reads the active DPI from.
    public let readStorage: DPIStorage
    /// USB interface (wIndex) that takes the control report.
    public let interface: UInt16
    /// Microseconds the firmware needs before its answer can be read.
    public let responseDelay: UInt32
    /// Battery-powered mice keep a temporary DPI until they power off, even when moved to another computer.
    public let batteryPowered: Bool
    /// Has on-mouse DPI stages (a DPI button switches to those).
    public let hasDPIStages: Bool
    public let support: Support

    public var dpiRange: ClosedRange<Int> { Self.minDPI...maxDPI }

    /// True when changing the DPI on the Mac can never change what other computers see.
    public var keepsOtherComputersDPI: Bool { writeStorage == .temporary && !batteryPowered }

    /// Whether the user must confirm once before the first write.
    public var needsConfirmation: Bool { support != .verified || !keepsOtherComputersDPI }

    /// Plain-language notes shown before the first write and in the UI.
    public var cautions: [String] {
        var notes: [String] = []
        if support == .untested {
            notes.append("This model hasn't been tested with DPI Switcher yet. Its settings come from OpenRazer.")
        }
        if writeStorage == .saved {
            notes.append("This model only accepts a DPI saved to its memory, so the new value also applies on your other computers. The original value is remembered so you can restore it.")
        } else if batteryPowered {
            notes.append("Wireless mice keep the Mac DPI until they power off, so it can carry over if you move the mouse to another computer.")
        } else {
            notes.append("The DPI is temporary: unplugging the mouse resets it to the value saved in the mouse.")
        }
        return notes
    }

    public func validate(dpi: Int) throws {
        guard dpiRange.contains(dpi) else {
            throw RazerError.invalidDPI("\(dpi) is outside \(dpiRange.lowerBound)–\(dpiRange.upperBound)")
        }
        guard dpi % Self.dpiStep == 0 else {
            throw RazerError.invalidDPI("\(dpi) must be a multiple of \(Self.dpiStep)")
        }
    }
}

public enum DeviceCatalog {
    public static let razerVendorID = 0x1532

    /// Only models listed here are ever written to. Generated from OpenRazer by
    /// scripts/generate-models.py (see Generated/ModelDatabase.swift).
    public static var models: [RazerModel] { generatedModels }

    public static func model(productID: Int) -> RazerModel? {
        models.first { $0.productID == productID }
    }

    /// Known Razer mice that this project deliberately does not support, and why.
    public static func exclusion(productID: Int) -> (name: String, reason: String)? {
        generatedExclusions[productID]
    }

    /// Transaction ids and interfaces used across Razer firmware generations,
    /// for read-only probing of unknown devices.
    static let candidateTransactionIDs: [UInt8] = [0xFF, 0x3F, 0x1F]
    static let candidateInterfaces: [UInt16] = [0, 3]
}
