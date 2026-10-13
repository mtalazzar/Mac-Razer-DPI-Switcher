#ifndef RAZER_USB_H
#define RAZER_USB_H

#include <stdint.h>
#include <IOKit/IOReturn.h>

/// HID class SET_REPORT (feature, report id 0) on the device's control pipe.
/// `location_id` selects the USB device (IOKit "locationID"); `interface` is wIndex.
IOReturn razer_usb_set_feature(uint32_t location_id, uint16_t interface, const uint8_t *data, uint16_t length);

/// HID class GET_REPORT (feature, report id 0). `*length` is in/out.
IOReturn razer_usb_get_feature(uint32_t location_id, uint16_t interface, uint8_t *data, uint16_t *length);

#endif
