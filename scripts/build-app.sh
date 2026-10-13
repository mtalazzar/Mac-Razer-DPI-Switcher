#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds "build/DPI Switcher.app" (menu bar app, CLI inside) and a build/dpiswitcher link.
#
# Usage: scripts/build-app.sh [--universal] [--zip] [--install]
#   --universal  build for both Apple Silicon and Intel
#   --zip        also create build/DPI-Switcher-<version>.zip for a GitHub release
#   --install    copy the app to /Applications and link the CLI into /usr/local/bin
#
# Environment:
#   BUNDLE_ID      bundle identifier (default io.github.dpi-switcher)
#   SIGN_IDENTITY  codesign identity (default "-" = ad-hoc). Set to a
#                  "Developer ID Application: …" identity to sign for distribution.
set -euo pipefail

cd "$(dirname "$0")/.."
BUNDLE_ID="${BUNDLE_ID:-io.github.dpi-switcher}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
VERSION="$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/RazerKit/ProjectInfo.swift)"
APP="build/DPI Switcher.app"

UNIVERSAL=0 ZIP=0 INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --universal) UNIVERSAL=1 ;;
        --zip) ZIP=1 ;;
        --install) INSTALL=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

BUILD_ARGS=(-c release)
[[ $UNIVERSAL == 1 ]] && BUILD_ARGS+=(--arch arm64 --arch x86_64)
swift build "${BUILD_ARGS[@]}" --product DPISwitcherApp
swift build "${BUILD_ARGS[@]}" --product dpiswitcher
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

rm -rf "$APP"
# Helpers/, not MacOS/: the default macOS filesystem is case-insensitive, so
# "dpiswitcher" would overwrite the "DPISwitcher" app binary.
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers"
cp "$BIN/DPISwitcherApp" "$APP/Contents/MacOS/DPISwitcher"
cp "$BIN/dpiswitcher" "$APP/Contents/Helpers/dpiswitcher"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>DPI Switcher</string>
    <key>CFBundleDisplayName</key><string>DPI Switcher</string>
    <key>CFBundleExecutable</key><string>DPISwitcher</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>GPL-3.0-or-later. Not affiliated with Razer Inc.</string>
</dict>
</plist>
PLIST

SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
[[ "$SIGN_IDENTITY" != "-" ]] && SIGN_ARGS+=(--options runtime --timestamp)
codesign "${SIGN_ARGS[@]}" "$APP/Contents/Helpers/dpiswitcher"
codesign "${SIGN_ARGS[@]}" "$APP"
ln -sf "DPI Switcher.app/Contents/Helpers/dpiswitcher" build/dpiswitcher
echo "Built $APP $VERSION ($(lipo -archs "$APP/Contents/MacOS/DPISwitcher"))"

if [[ $ZIP == 1 ]]; then
    ZIPFILE="build/DPI-Switcher-${VERSION}.zip"
    rm -f "$ZIPFILE"
    ditto -c -k --keepParent "$APP" "$ZIPFILE"
    echo "Created $ZIPFILE"
fi

if [[ $INSTALL == 1 ]]; then
    pkill -x DPISwitcher 2>/dev/null && sleep 1 || true
    rm -rf "/Applications/DPI Switcher.app"
    cp -R "$APP" /Applications/
    ln -sf "/Applications/DPI Switcher.app/Contents/Helpers/dpiswitcher" /usr/local/bin/dpiswitcher 2>/dev/null \
        || echo "note: couldn't link /usr/local/bin/dpiswitcher (not writable)"
    echo "Installed /Applications/DPI Switcher.app"
fi
