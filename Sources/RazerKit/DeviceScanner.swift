// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import IOKit

/// A Razer USB device as seen on the bus, supported or not.
public struct DetectedDevice: Equatable, Identifiable {
    public let productID: Int
    /// IOKit locationID: unique per USB port, used to address the device.
    public let locationID: UInt32
    public let usbName: String
    public let firmware: String
    /// Has a HID boot-mouse interface (class 3, protocol 2).
    public let looksLikeMouse: Bool

    public var id: UInt32 { locationID }
    public var model: RazerModel? { DeviceCatalog.model(productID: productID) }
    public var exclusion: (name: String, reason: String)? { DeviceCatalog.exclusion(productID: productID) }
    public var displayName: String { model?.name ?? exclusion?.name ?? usbName }
    public var usbID: String { String(format: "1532:%04X", productID) }

    public static func == (a: Self, b: Self) -> Bool {
        a.productID == b.productID && a.locationID == b.locationID
    }
}

public enum DeviceScanner {
    /// All Razer USB devices currently connected, ordered by port.
    public static func scan() -> [DetectedDevice] {
        let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        matching[kIOPropertyMatchKey] = ["idVendor": DeviceCatalog.razerVendorID]

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var devices: [DetectedDevice] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let pid = property(service, "idProduct") as? Int,
                  let location = property(service, "locationID") as? Int else { continue }
            let bcd = property(service, "bcdDevice") as? Int ?? 0
            let name = (property(service, "USB Product Name") ?? property(service, "kUSBProductString")) as? String
            devices.append(DetectedDevice(
                productID: pid,
                locationID: UInt32(truncatingIfNeeded: location),
                usbName: name ?? "Razer device",
                firmware: String(format: "%d.%02x", bcd >> 8, bcd & 0xFF),
                looksLikeMouse: hasMouseInterface(service)
            ))
        }
        return devices.sorted { $0.locationID < $1.locationID }
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func hasMouseInterface(_ service: io_service_t) -> Bool {
        var children: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &children) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(children) }
        var found = false
        while case let child = IOIteratorNext(children), child != 0 {
            if property(child, "bInterfaceClass") as? Int == 3, property(child, "bInterfaceProtocol") as? Int == 2 {
                found = true
            }
            IOObjectRelease(child)
        }
        return found
    }
}
