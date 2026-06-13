#!/usr/bin/env bash
# Build TokenMeter as a proper .app bundle the user can double-click.
# Embeds AppIcon.icns + entitlements (App Sandbox, network.client,
# user-selected file read-only) and applies ad-hoc code signing.
#
# Flags:
#   --debug           build the debug Swift configuration
#   --no-sandbox      omit entitlements (purely local builds without sandbox)
#
# Real notarization still needs an Apple Developer ID — out of scope for
# this script. See the README "App Store" section.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="release"
SANDBOX=1
for arg in "$@"; do
    case "$arg" in
        --debug)      CONFIG="debug" ;;
        --no-sandbox) SANDBOX=0 ;;
    esac
done

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

# ---------- 3b. Localizations ----------
# SwiftUI Text("key") and NSLocalizedString look up via Bundle.main, but SPM
# packages the .strings inside a nested resource bundle. Copy the .lproj
# folders to the .app's main Resources so the lookups resolve.
SPM_BUNDLE_NAME="TokenMeter_TokenMeter.bundle"
SPM_BUNDLE_PATH="$BIN_DIR/$SPM_BUNDLE_NAME"
if [[ -d "$SPM_BUNDLE_PATH" ]]; then
    for lproj in "$SPM_BUNDLE_PATH"/*.lproj; do
        [[ -d "$lproj" ]] || continue
        cp -R "$lproj" "$APP/Contents/Resources/"
    done
fi

# ---------- 4. Ad-hoc code sign ----------
# Real notarization needs a Developer ID + Apple ID + app-specific password.
# Ad-hoc signing (identity "-") gives the bundle a stable signature and lets
# Launch Services trust it across relaunches on this machine.
echo "▸ ad-hoc code signing (sandbox=$SANDBOX)"
SIGN_ARGS=(--force --deep --sign -)
if [[ "$SANDBOX" == "1" ]]; then
    SIGN_ARGS+=(--entitlements TokenMeter.entitlements -o runtime)
fi
codesign "${SIGN_ARGS[@]}" "$APP" 2>&1 | grep -v "replacing existing signature" || true
codesign --verify --verbose=2 "$APP" 2>&1 | tail -3
codesign -d --entitlements - "$APP" 2>&1 | grep -i "app-sandbox" || true

echo "✓ built $APP"
echo "   open with: open $APP"
