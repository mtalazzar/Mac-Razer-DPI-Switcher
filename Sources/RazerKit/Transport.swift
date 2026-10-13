// SPDX-License-Identifier: GPL-3.0-or-later

import CRazerUSB
import Foundation
import IOKit

/// Sends Razer reports as HID class control requests on the device's control
/// pipe (see CRazerUSB). The HID interfaces are never opened, so no Input
/// Monitoring permission is needed and the pointer is never interrupted.
enum Transport {
    /// One request/response at a time per process; the firmware handles one report at a time.
    private static let lock = NSLock()

    static func send(_ command: RazerCommand, location: UInt32, interface: UInt16,
                     transactionID: UInt8, responseDelay: UInt32) throws -> RazerReport {
        lock.lock()
        defer { lock.unlock() }

        let request = command.report(transactionID: transactionID).encoded()
        let setResult = request.withUnsafeBufferPointer {
            razer_usb_set_feature(location, interface, $0.baseAddress!, UInt16($0.count))
        }
        if setResult == kIOReturnNoDevice { throw RazerError.noDevice }
        guard setResult == kIOReturnSuccess else { throw RazerError.ioFailed("Sending to the mouse", setResult) }

        // The firmware needs a moment to process (up to ~0.4 s on some wireless
        // receivers) and answers "busy" until done.
        let firstWait = max(responseDelay, 2_000)
        let retryWait = max(responseDelay / 4, 8_000)
        var lastError: Error = RazerError.noResponse
        for attempt in 0..<12 {
            usleep(attempt == 0 ? firstWait : retryWait)
            var buffer = [UInt8](repeating: 0, count: RazerReport.size)
            var length = UInt16(buffer.count)
            let getResult = buffer.withUnsafeMutableBufferPointer {
                razer_usb_get_feature(location, interface, $0.baseAddress!, &length)
            }
            if getResult == kIOReturnNoDevice { throw RazerError.noDevice }
            guard getResult == kIOReturnSuccess else {
                lastError = RazerError.ioFailed("Reading from the mouse", getResult)
                continue
            }
            guard length == RazerReport.size, let response = RazerReport(bytes: buffer) else { continue }

            switch response.parsedStatus {
            case .busy, .new:
                continue
            case .success where command.matches(response, transactionID: transactionID):
                return response
            case .success:
                continue // a stale answer to something else
            case .timeout:
                throw RazerError.notResponding
            default:
                throw RazerError.deviceStatus(response.status)
            }
        }
        throw lastError
    }
}
