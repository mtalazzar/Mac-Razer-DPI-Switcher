// Feature reports sent as raw HID class control requests on the default
// control pipe — the same transfer OpenRazer issues on Linux
// (usb_control_msg with HID_REQ_SET_REPORT / HID_REQ_GET_REPORT).
//
// Going through the device's control pipe instead of IOHIDDeviceOpen means the
// mouse's HID interfaces are never opened, so macOS does not require the
// Input Monitoring permission and pointer input is never interrupted.

#include "razer_usb.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>

#define HID_REQ_GET_REPORT 0x01
#define HID_REQ_SET_REPORT 0x09
#define HID_FEATURE_REPORT_ID0 0x0300

static IOUSBDeviceInterface182 **open_device_interface(uint32_t location_id, IOReturn *error) {
    *error = kIOReturnNoDevice;

    // IOUSBHostDevice is the device class since macOS 10.11 (AppleUSBDevice on 13).
    CFMutableDictionaryRef match = IOServiceMatching("IOUSBHostDevice");
    if (!match) return NULL;
    CFMutableDictionaryRef props = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                             &kCFTypeDictionaryKeyCallBacks,
                                                             &kCFTypeDictionaryValueCallBacks);
    CFNumberRef loc = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &location_id);
    CFDictionarySetValue(props, CFSTR(kUSBDevicePropertyLocationID), loc);
    CFDictionarySetValue(match, CFSTR(kIOPropertyMatchKey), props);
    CFRelease(loc);
    CFRelease(props);

    // Consumes `match`.
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, match);
    if (!service) return NULL;

    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    IOReturn kr = IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID,
                                                    kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(service);
    if (kr != kIOReturnSuccess || !plugin) {
        *error = kr ? kr : kIOReturnError;
        return NULL;
    }

    IOUSBDeviceInterface182 **dev = NULL;
    HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID182), (LPVOID *)&dev);
    IODestroyPlugInInterface(plugin);
    if (hr != S_OK || !dev) {
        *error = kIOReturnUnsupported;
        return NULL;
    }
    *error = kIOReturnSuccess;
    return dev;
}

static IOReturn control(uint32_t location_id, UInt8 request_type, UInt8 request,
                        uint16_t interface, void *data, uint16_t *length) {
    IOReturn kr;
    IOUSBDeviceInterface182 **dev = open_device_interface(location_id, &kr);
    if (!dev) return kr;

    IOUSBDevRequestTO req = {
        .bmRequestType = request_type,
        .bRequest = request,
        .wValue = HID_FEATURE_REPORT_ID0,
        .wIndex = interface,
        .wLength = *length,
        .pData = data,
        .wLenDone = 0,
        .noDataTimeout = 1000,
        .completionTimeout = 1000,
    };
    kr = (*dev)->DeviceRequestTO(dev, &req);
    *length = (uint16_t)req.wLenDone;
    (*dev)->Release(dev);
    return kr;
}

IOReturn razer_usb_set_feature(uint32_t location_id, uint16_t interface, const uint8_t *data, uint16_t length) {
    uint16_t len = length;
    return control(location_id, USBmakebmRequestType(kUSBOut, kUSBClass, kUSBInterface),
                   HID_REQ_SET_REPORT, interface, (void *)data, &len);
}

IOReturn razer_usb_get_feature(uint32_t location_id, uint16_t interface, uint8_t *data, uint16_t *length) {
    return control(location_id, USBmakebmRequestType(kUSBIn, kUSBClass, kUSBInterface),
                   HID_REQ_GET_REPORT, interface, data, length);
}
