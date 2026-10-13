# RazerDPI

A small macOS menu bar app (plus CLI) that sets the DPI of a **Razer DeathAdder
Essential** (USB `1532:006E`) on an Intel Mac, where Razer Synapse isn't available.

The Mac DPI is set as a **temporary** value. The mouse forgets it when it's
unplugged, so on Windows the mouse starts with its own **saved** DPI as before.
Nothing is ever written to the saved value, with or without Synapse running.

## Install

```bash
scripts/build-app.sh --install
```

This builds `RazerDPI.app` into `/Applications` and links the `razerdpi` CLI into
`/usr/local/bin`. The app is ad-hoc signed for local use, so no Apple developer
account is needed.

## Use

The menu bar icon shows the current DPI. From the menu you can:

- pick a preset (default **800 / 1600**). The chosen one is the "Mac DPI".
- **Apply When Mouse Connects** (on by default) re-applies the Mac DPI each time
  the mouse is plugged in and after the Mac wakes from sleep.
- **Edit Presets…**
- **Open at Login** (off by default). Auto-apply only works while the app is
  running, so turn this on if you want it to always happen.

CLI:

```
razerdpi list        connected supported mice
razerdpi get         current and saved DPI
razerdpi set 1600    temporary DPI (saved value untouched)
razerdpi probe       read-only protocol check
```

macOS's own *Tracking speed* (System Settings → Mouse) multiplies on top of the
DPI. RazerDPI doesn't change it.

## How it works

Razer mice take a 90-byte HID feature report on USB interface 0. The format is
documented by [OpenRazer](https://github.com/openrazer/openrazer):

| bytes | field |
|---|---|
| 0 | status (0x02 = ok, 0x01 = busy, 0x03 = fail, 0x05 = unsupported) |
| 1 | transaction id (0xFF for this model) |
| 5 | data size |
| 6–7 | command class / id: `04 05` set DPI, `04 85` get DPI |
| 8 | storage: `00` temporary (NOSTORE), `01` saved (VARSTORE) |
| 9–12 | DPI X, DPI Y (big endian) |
| 88 | CRC = XOR of bytes 2–87 |

The report is sent as a HID class `SET_REPORT` / `GET_REPORT` control
request on the device's control pipe (`Sources/CRazerUSB`). The mouse's HID
interfaces are never opened, so:

- no **Input Monitoring** permission is needed,
- macOS never loses the pointer, even while the DPI is being changed.

### Safety rules in the code

- Only *get DPI* and *set DPI* can be encoded (`RazerCommand` is an allowlist).
  No firmware, flash or device-mode commands exist in this codebase.
- Writes are refused for any model not in `DeviceCatalog`, or whose transaction
  id hasn't been confirmed on real hardware.
- DPI is validated (200–6400, steps of 100), and every write is read back.
- The app reads first and only writes if the DPI differs.

### Verified on hardware (firmware 2.00)

- Reads answered: current 600 and saved 600, matching the Windows setting.
- `set 1600` → current 1600, saved 600. Unplug/replug → back to 600/600.

## Development

```bash
swift build
swift test
swift run razerdpi get
```

Adding another model means adding a `RazerModel` to `DeviceCatalog.swift` with
its USB product id and the transaction id OpenRazer uses for it, then running
`razerdpi probe` against the real device.
