// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import RazerKit

final class CatalogTests: XCTestCase {
    /// The hardware-verified DeathAdder Essential must keep exactly the settings tested on it.
    func testVerifiedDeathAdderEssential() throws {
        let m = try XCTUnwrap(DeviceCatalog.model(productID: 0x006E))
        XCTAssertEqual(m.support, .verified)
        XCTAssertEqual(m.transactionID, 0xFF)
        XCTAssertEqual(m.writeStorage, .temporary)
        XCTAssertEqual(m.readStorage, .temporary)
        XCTAssertEqual(m.interface, 0)
        XCTAssertEqual(m.maxDPI, 6400)
        XCTAssertFalse(m.batteryPowered)
        XCTAssertTrue(m.keepsOtherComputersDPI)
        XCTAssertFalse(m.needsConfirmation)
    }

    func testCatalogIsSane() {
        let models = DeviceCatalog.models
        XCTAssertGreaterThan(models.count, 50)
        XCTAssertEqual(Set(models.map(\.productID)).count, models.count, "duplicate product ids")
        for m in models {
            XCTAssertTrue([0xFF, 0x3F, 0x1F].contains(m.transactionID), m.name)
            XCTAssertTrue([0, 3].contains(m.interface), m.name)
            XCTAssertTrue((1000...50000).contains(m.maxDPI), m.name)
            XCTAssertNil(DeviceCatalog.exclusion(productID: m.productID), m.name)
            XCTAssertFalse(m.name.isEmpty)
        }
    }

    func testSpotChecksAgainstOpenRazer() throws {
        // Interface 3 (razer_get_report index = 0x03)
        XCTAssertEqual(DeviceCatalog.model(productID: 0x0099)?.interface, 3) // Basilisk V3
        // 0x3F transaction id, wireless, long receiver wait
        let daV2Pro = try XCTUnwrap(DeviceCatalog.model(productID: 0x007D)) // DeathAdder V2 Pro (Wireless)
        XCTAssertEqual(daV2Pro.transactionID, 0x3F)
        XCTAssertTrue(daV2Pro.batteryPowered)
        XCTAssertGreaterThanOrEqual(daV2Pro.responseDelay, 31_000)
        // VARSTORE writer
        XCTAssertEqual(DeviceCatalog.model(productID: 0x0096)?.writeStorage, .saved) // Naga X
    }

    func testOldProtocolsAreExcluded() {
        XCTAssertNil(DeviceCatalog.model(productID: 0x0016)) // DeathAdder 3.5G
        XCTAssertNotNil(DeviceCatalog.exclusion(productID: 0x0016))
        XCTAssertNil(DeviceCatalog.model(productID: 0x0041)) // Naga Hex, 1-byte DPI
    }

    func testCautions() throws {
        let untestedWireless = try XCTUnwrap(DeviceCatalog.model(productID: 0x007D))
        XCTAssertTrue(untestedWireless.needsConfirmation)
        XCTAssertEqual(untestedWireless.cautions.count, 2)
        let saved = try XCTUnwrap(DeviceCatalog.model(productID: 0x0096))
        XCTAssertFalse(saved.keepsOtherComputersDPI)
    }
}
