#!/bin/bash
# Builds build/RazerDPI.app (menu bar app, CLI inside) and a build/razerdpi link.
# Usage: scripts/build-app.sh [--install]
#   --install  copy the app to /Applications and link the CLI into /usr/local/bin
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="1.0.0"
APP="build/RazerDPI.app"

swift build -c release --product RazerDPIApp
swift build -c release --product razerdpi
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
# Helpers/, not MacOS/: the default macOS filesystem is case-insensitive, so
# "razerdpi" would overwrite the "RazerDPI" app binary.
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers"
cp "$BIN/RazerDPIApp" "$APP/Contents/MacOS/RazerDPI"
cp "$BIN/razerdpi" "$APP/Contents/Helpers/razerdpi"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.mattia.razerdpi</string>
    <key>CFBundleName</key><string>RazerDPI</string>
    <key>CFBundleDisplayName</key><string>RazerDPI</string>
    <key>CFBundleExecutable</key><string>RazerDPI</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run locally, no Apple developer account needed.
codesign --force --sign - "$APP/Contents/Helpers/razerdpi"
codesign --force --sign - "$APP"
ln -sf "RazerDPI.app/Contents/Helpers/razerdpi" build/razerdpi
echo "Built $APP (CLI: build/razerdpi)"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x RazerDPI 2>/dev/null && sleep 1 || true
    rm -rf /Applications/RazerDPI.app
    cp -R "$APP" /Applications/
    ln -sf /Applications/RazerDPI.app/Contents/Helpers/razerdpi /usr/local/bin/razerdpi 2>/dev/null || true
    echo "Installed /Applications/RazerDPI.app"
fi
