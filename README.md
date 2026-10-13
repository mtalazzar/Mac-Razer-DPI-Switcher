# DPI Switcher

A small, native macOS menu bar app for changing the DPI of Razer mice, for when
Razer Synapse isn't an option on your Mac.

- **Leaves your other computers alone.** On wired mice the DPI is set *temporarily*:
  the mouse forgets it when unplugged, so on your Windows PC it starts with
  its own saved DPI as before.
- **No permissions, no drivers.** Nothing to install besides the app, and no
  Input Monitoring or Accessibility access.
- **Detects your mouse** and applies your Mac DPI each time it's plugged in.
- **Presets per mouse**, plus a `dpiswitcher` command-line tool.

> DPI Switcher is an independent open-source project. It is not affiliated with,
> endorsed by, or supported by Razer Inc. "Razer" and product names are
> trademarks of their respective owners.

## Supported mice

**104 models** based on [OpenRazer](https://github.com/openrazer/openrazer)'s
protocol data. See the full list in [docs/SUPPORTED_MICE.md](docs/SUPPORTED_MICE.md).

| Status | Meaning |
|---|---|
| ✅ Verified | Tested on real hardware with DPI Switcher. |
| Untested | Should work. The app asks you to confirm once. Please [report the result](CONTRIBUTING.md#report-your-mouse). |

Verified so far: **Razer DeathAdder Essential** (`1532:006E`).

Your mouse isn't listed? The app shows it as *not supported* and has a
**Report This Mouse** button that opens a pre-filled GitHub issue.

## Install

Requires macOS 13 Ventura or later, on Intel or Apple Silicon.

1. Download `DPI-Switcher-<version>.zip` from [Releases](../../releases) and unzip it.
2. Move **DPI Switcher.app** to **Applications**.
3. Open it. The app isn't notarized by Apple yet, so macOS blocks the first launch:
   - **macOS 13–14:** right-click the app → **Open** → **Open**.
   - **macOS 15+:** try to open it once, then go to **System Settings → Privacy &
     Security**, scroll down and click **Open Anyway**.

To use the command-line tool, link it into your PATH:

```bash
ln -s "/Applications/DPI Switcher.app/Contents/Helpers/dpiswitcher" /usr/local/bin/dpiswitcher
```

## Use

Click the mouse icon in the menu bar (it shows the current DPI):

- **Presets:** pick one to make it your Mac DPI. Edit them under **Edit Presets…**.
- **Apply When Mouse Connects** (on by default) re-applies the Mac DPI on plug-in
  and after sleep.
- **Open at Login:** the app only applies the DPI while it's running, so turn this on.
- **Saved in mouse (other computers)** shows the DPI your other computers will see.

Command line:

```
dpiswitcher list              connected Razer mice and their support status
dpiswitcher get               current DPI (and the DPI saved in the mouse)
dpiswitcher set 1600          set the DPI
dpiswitcher report            diagnostics to paste into a GitHub issue
dpiswitcher models            every supported model
```

Use `-d 2` to choose the second mouse from `list`. For models that need
confirmation, `set` asks you to add `--yes`.

### Good to know

- **Wireless mice** keep the Mac DPI until they power off, so it can carry over if
  you move the receiver to another computer. The app warns about this.
- **Bluetooth** isn't supported. DPI commands need a USB connection (cable or receiver).
- **A few models only accept a saved DPI** (marked in the list). On those, the
  change also applies on other computers. The app remembers the original value
  and offers **Restore Original DPI**.
- **DPI buttons** on the mouse switch to the mouse's own stored DPI stages. Pick a
  preset again to go back.
- macOS's own **Tracking speed** (System Settings → Mouse) multiplies on top of the DPI.
- DPI values go from 200 up to the model's maximum, in steps of 50.

## How it works

Razer mice take a 90-byte HID feature report, whose format is documented by
OpenRazer:

| Bytes | Field |
|---|---|
| 0 | status (`02` ok, `01` busy, `03` failed, `04` timeout, `05` unsupported) |
| 1 | transaction id (`FF`, `3F` or `1F` depending on the model) |
| 5 | data size |
| 6–7 | command: `04 05` set DPI, `04 85` get DPI |
| 8 | storage: `00` temporary, `01` saved |
| 9–12 | DPI X and Y, big endian |
| 88 | checksum: XOR of bytes 2–87 |

DPI Switcher sends it as a standard HID `SET_REPORT` / `GET_REPORT` control
request on the mouse's USB control pipe (`Sources/CRazerUSB`). It never opens
the mouse's HID interfaces, which is why no permission is needed and the pointer
keeps working while the DPI changes.

### Safety

- The code can only build two commands: **get DPI** and **set DPI**
  (`RazerCommand` is an allowlist). It contains no firmware, flash or
  device-mode commands.
- It only writes to models in the generated catalog, after validating the value
  against the model's range.
- Every write is read back. If the mouse reports a different value, the
  previous DPI is put back.
- Untested models, wireless models and saved-only models need a one-time confirmation.

## Build from source

```bash
swift test
scripts/build-app.sh --install    # builds and installs to /Applications
```

`scripts/build-app.sh --universal --zip` builds the release zip.
`SIGN_IDENTITY="Developer ID Application: …"` signs it for distribution.

The model database is generated from OpenRazer:

```bash
scripts/update-models.sh          # latest OpenRazer
```

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits and license

Protocol and model data come from [OpenRazer](https://github.com/openrazer/openrazer)
(GPL-2.0-or-later). Many thanks to its contributors.

DPI Switcher is licensed under the [GNU General Public License v3.0 or later](LICENSE).
