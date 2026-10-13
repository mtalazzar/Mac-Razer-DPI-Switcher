# Contributing

## Report your mouse

The most useful contribution is telling us whether your mouse works.

1. Plug the mouse in with a cable or its USB receiver.
2. In the app, choose **Report How It Works on GitHub…** for your mouse (or
   **Report This Mouse…** if it isn't supported). This copies a diagnostic report
   and opens a pre-filled issue. From the terminal, run `dpiswitcher report`.
3. Check what you can (pointer speed changes, replugging resets it on wired mice)
   and submit.

`report` only reads from the mouse. For mice that aren't in the catalog it tries
the known protocol variants **read-only**, which is enough to add them.

## Marking a model as verified

A maintainer adds an entry to `data/verified-models.json` with the USB id,
firmware, macOS version and what was tested, then regenerates:

```bash
scripts/update-models.sh <openrazer-commit>   # the commit in ModelDatabase.swift
```

## Updating the model database

```bash
scripts/update-models.sh            # latest OpenRazer master
swift test
```

Review the diff of `Sources/RazerKit/Generated/ModelDatabase.swift` and
`docs/SUPPORTED_MICE.md`. CI fails if the generated files don't match the generator.
Never edit the generated files by hand. Change `scripts/generate-models.py` instead.

## Code

- `Sources/RazerKit`: protocol, model catalog, USB transport and device discovery.
- `Sources/CRazerUSB`: the USB control request (C, IOKit).
- `Sources/DPISwitcherApp`: SwiftUI menu bar app.
- `Sources/dpiswitcher`: command-line tool.

Safety rules for changes:

- Keep `RazerCommand` limited to DPI commands. Adding any other command class
  (lighting, polling rate, …) needs an issue first, and firmware, flash and
  device-mode commands won't be accepted.
- Writes must stay limited to catalog models and validated values, with read-back.
- Don't open HID devices (`IOHIDDeviceOpen`). That would require Input Monitoring.

By contributing you agree that your contributions are licensed under
GPL-3.0-or-later.
