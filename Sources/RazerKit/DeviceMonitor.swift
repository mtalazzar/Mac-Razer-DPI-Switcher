// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import IOKit

/// Calls `onChange` on the main queue whenever a Razer USB device is plugged in
/// or removed. Uses IOKit service notifications, which need no permissions and
/// never open the device.
public final class DeviceMonitor {
    private let onChange: () -> Void
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    public init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    deinit { stop() }

    public func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)

        let context = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
            matching[kIOPropertyMatchKey] = ["idVendor": DeviceCatalog.razerVendorID]

            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(port, type, matching, { context, iterator in
                let monitor = Unmanaged<DeviceMonitor>.fromOpaque(context!).takeUnretainedValue()
                DeviceMonitor.drain(iterator)
                monitor.onChange()
            }, context, &iterator)
            guard result == kIOReturnSuccess else { continue }
            // Draining arms the notification; existing devices are reported via
            // the initial onChange below instead.
            Self.drain(iterator)
            iterators.append(iterator)
        }
        onChange()
    }

    public func stop() {
        iterators.forEach { IOObjectRelease($0) }
        iterators.removeAll()
        if let port { IONotificationPortDestroy(port) }
        port = nil
    }

    private static func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
        }
    }
}
