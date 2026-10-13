// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import RazerKit

final class RazerReportTests: XCTestCase {
    func testGetDPIEncoding() {
        let bytes = RazerCommand.getDPI(.temporary).report(transactionID: 0x3F).encoded()
        XCTAssertEqual(bytes.count, 90)
        XCTAssertEqual(Array(bytes[0..<9]), [0x00, 0x3F, 0x00, 0x00, 0x00, 0x07, 0x04, 0x85, 0x00])
        XCTAssertTrue(bytes[9..<88].allSatisfy { $0 == 0 })
        XCTAssertEqual(bytes[88], 0x07 ^ 0x04 ^ 0x85)
        XCTAssertEqual(bytes[89], 0x00)
    }

    func testSetDPIEncoding() {
        // 800 DPI = 0x0320, temporary storage (NOSTORE)
        let bytes = RazerCommand.setDPI(.temporary, x: 800, y: 800).report(transactionID: 0x1F).encoded()
        XCTAssertEqual(Array(bytes[0..<15]),
                       [0x00, 0x1F, 0x00, 0x00, 0x00, 0x07, 0x04, 0x05,
                        0x00, 0x03, 0x20, 0x03, 0x20, 0x00, 0x00])
        XCTAssertTrue(bytes[15..<88].allSatisfy { $0 == 0 })
        XCTAssertEqual(bytes[88], 0x06) // 07^04^05^00^03^20^03^20
    }

    func testSavedStorageByte() {
        let bytes = RazerCommand.setDPI(.saved, x: 600, y: 600).report(transactionID: 0x3F).encoded()
        XCTAssertEqual(bytes[8], 0x01)
        XCTAssertEqual(Array(bytes[9..<13]), [0x02, 0x58, 0x02, 0x58])
    }

    func testCRCIgnoresStatusAndTransactionID() {
        let a = RazerCommand.getDPI(.saved).report(transactionID: 0x1F).encoded()
        let b = RazerCommand.getDPI(.saved).report(transactionID: 0xFF).encoded()
        XCTAssertEqual(a[88], b[88])
    }

    func testParseResponse() {
        var bytes = RazerCommand.getDPI(.temporary).report(transactionID: 0x3F).encoded()
        bytes[0] = RazerReport.Status.success.rawValue
        bytes.replaceSubrange(9..<13, with: [0x02, 0x58, 0x02, 0x58]) // 600 x 600
        let response = RazerReport(bytes: bytes)!
        XCTAssertEqual(response.parsedStatus, .success)
        XCTAssertTrue(RazerCommand.getDPI(.temporary).matches(response, transactionID: 0x3F))
        XCTAssertFalse(RazerCommand.getDPI(.temporary).matches(response, transactionID: 0x1F))
        XCTAssertEqual(DPIValue(response: response), DPIValue(x: 600, y: 600))
    }

    func testRoundTrip() {
        let report = RazerCommand.setDPI(.temporary, x: 1600, y: 1600).report(transactionID: 0x3F)
        XCTAssertEqual(RazerReport(bytes: report.encoded()), report)
        XCTAssertNil(RazerReport(bytes: [0x00, 0x01]))
    }

    func testValidation() throws {
        let model = DeviceCatalog.model(productID: 0x006E)!
        XCTAssertNoThrow(try model.validate(dpi: 800))
        XCTAssertNoThrow(try model.validate(dpi: 6400))
        XCTAssertThrowsError(try model.validate(dpi: 150))
        XCTAssertNoThrow(try model.validate(dpi: 200))
        XCTAssertThrowsError(try model.validate(dpi: 6450))
        XCTAssertThrowsError(try model.validate(dpi: 825))
    }

    func testUnknownProductIsNotSupported() {
        XCTAssertNil(DeviceCatalog.model(productID: 0xFFFF))
    }
}
