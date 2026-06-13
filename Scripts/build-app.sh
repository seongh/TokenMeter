#!/usr/bin/env bash
# Build TokenMeter as a proper .app bundle the user can double-click.
# Embeds AppIcon.icns and applies ad-hoc code signing so macOS treats the
# bundle as a real signed app (no Gatekeeper warning on first launch from
# the same machine; real notarization still needs a Developer ID).
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="release"
[[ "${1-}" == "--debug" ]] && CONFIG="debug"

# ---------- 1. Swift build ----------
echo "▸ swift build ($CONFIG)"
swift build -c "$CONFIG"

BIN_DIR=".build/$( [[ "$CONFIG" == "release" ]] && echo "release" || echo "debug" )"
BIN="$BIN_DIR/TokenMeter"
[[ -x "$BIN" ]] || { echo "✗ binary not found at $BIN" >&2; exit 1; }

# ---------- 2. Icon ----------
ICON_SRC="Assets/icon_1024.png"
ICON_ICNS="Assets/AppIcon.icns"
if [[ ! -f "$ICON_SRC" ]]; then
    echo "▸ generating $ICON_SRC"
    swift Scripts/make-icon.swift
fi
if [[ ! -f "$ICON_ICNS" || "$ICON_SRC" -nt "$ICON_ICNS" ]]; then
    echo "▸ building $ICON_ICNS from $ICON_SRC"
    ICONSET=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET"
    sips -z 16 16     "$ICON_SRC" --out "$ICONSET/icon_16x16.png"      >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_32x32.png"      >/dev/null
    sips -z 64 64     "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
    sips -z 128 128   "$ICON_SRC" --out "$ICONSET/icon_128x128.png"    >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_256x256.png"    >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_512x512.png"    >/dev/null
    cp "$ICON_SRC"                "$ICONSET/icon_512x512@2x.png"
    iconutil -c icns -o "$ICON_ICNS" "$ICONSET"
    rm -rf "$ICONSET"
fi

# ---------- 3. Bundle ----------
APP="./TokenMeter.app"
echo "▸ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TokenMeter"
cp Info.plist "$APP/Contents/Info.plist"
cp "$ICON_ICNS" "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/TokenMeter"

# ---------- 4. Ad-hoc code sign ----------
# Real notarization needs a Developer ID + Apple ID + app-specific password.
# Ad-hoc signing (identity "-") gives the bundle a stable signature and lets
# Launch Services trust it across relaunches on this machine.
echo "▸ ad-hoc code signing"
codesign --force --deep --sign - "$APP" 2>&1 | grep -v "replacing existing signature" || true
codesign --verify --verbose=2 "$APP" 2>&1 | tail -3

echo "✓ built $APP"
echo "   open with: open $APP"
