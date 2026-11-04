#!/usr/bin/env bash
# shellcheck shell=bash
# build.sh — Compile ClaudeUsageMonitor and produce a DMG for distribution.
# Works with only Xcode Command Line Tools installed (no Xcode.app required).
#
# Usage:
#   ./scripts/build.sh             # builds current arch
#   ./scripts/build.sh --version 1.2.0
#   ./scripts/build.sh --universal  # arm64 + x86_64 fat binary
#   ./scripts/build.sh --no-install # skip replacing /Applications copy
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SOURCE_DIR="$PROJECT_DIR/ClaudeUsageMonitor"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"

APP_NAME="ClaudeUsageMonitor"
BUNDLE_ID="com.yourname.ClaudeUsageMonitor"
VERSION="1.5.0"
UNIVERSAL=false
INSTALL=true
INSTALL_PATH="/Applications/$APP_NAME.app"

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --version) VERSION="$2"; shift 2 ;;
    --universal) UNIVERSAL=true; shift ;;
    --no-install) INSTALL=false; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
HOST_ARCH="$(uname -m)"   # arm64 or x86_64

echo "╔══════════════════════════════════════╗"
echo "║  Building $APP_NAME v$VERSION"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Collect sources ───────────────────────────────────────────────────────────
# Use a temp file to avoid bash 3 mapfile incompatibility (macOS ships bash 3.2)
SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(find "$SOURCE_DIR" -name "*.swift" | sort)
echo "▸ ${#SOURCES[@]} Swift files found"

mkdir -p "$BUILD_DIR"

# ── Common swiftc flags ───────────────────────────────────────────────────────
SWIFT_FLAGS=(
  -sdk "$SDK_PATH"
  -module-name "$APP_NAME"
  -Xlinker -rpath -Xlinker "@executable_path/../Frameworks"
  -framework SwiftUI
  -framework AppKit
  -framework WebKit
  -framework UserNotifications
  -framework Combine
  -framework Foundation
)

# ── Compile ───────────────────────────────────────────────────────────────────
if $UNIVERSAL; then
  echo "▸ Compiling arm64..."
  swiftc "${SWIFT_FLAGS[@]}" -target "arm64-apple-macos13.0" \
    "${SOURCES[@]}" -o "$BUILD_DIR/${APP_NAME}_arm64"

  echo "▸ Compiling x86_64..."
  swiftc "${SWIFT_FLAGS[@]}" -target "x86_64-apple-macos13.0" \
    "${SOURCES[@]}" -o "$BUILD_DIR/${APP_NAME}_x86_64"

  echo "▸ Creating universal binary..."
  lipo -create \
    "$BUILD_DIR/${APP_NAME}_arm64" \
    "$BUILD_DIR/${APP_NAME}_x86_64" \
    -output "$BUILD_DIR/$APP_NAME"
  rm "$BUILD_DIR/${APP_NAME}_arm64" "$BUILD_DIR/${APP_NAME}_x86_64"
else
  echo "▸ Compiling ($HOST_ARCH)..."
  swiftc "${SWIFT_FLAGS[@]}" -target "${HOST_ARCH}-apple-macos13.0" \
    "${SOURCES[@]}" -o "$BUILD_DIR/$APP_NAME"
fi
echo "✔ Binary compiled"

# ── Assemble .app bundle ──────────────────────────────────────────────────────
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Copy icon
if [ -f "$SOURCE_DIR/Assets/AppIcon.icns" ]; then
  cp "$SOURCE_DIR/Assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
  echo "✔ Icon copied"
else
  echo "⚠  AppIcon.icns not found — app will use default icon"
fi

# Copy menu bar icon (small PNG, loaded directly to avoid macOS background compositing)
if [ -f "$SOURCE_DIR/Assets/MenuBarIcon.png" ]; then
  cp "$SOURCE_DIR/Assets/MenuBarIcon.png" "$APP_BUNDLE/Contents/Resources/"
  echo "✔ Menu bar icon copied"
fi

# ── Ad-hoc code sign ─────────────────────────────────────────────────────────
codesign --force --deep --sign - "$APP_BUNDLE"
echo "✔ Signed (ad-hoc)"

# ── Install in place ─────────────────────────────────────────────────────────
# Replaces the installed copy and relaunches it, so only one binary ever reads
# the Keychain item (ad-hoc signatures get a Keychain prompt per new binary).
if $INSTALL; then
  pkill -x "$APP_NAME" 2>/dev/null && sleep 1 || true
  rm -rf "$INSTALL_PATH"
  cp -R "$APP_BUNDLE" "$INSTALL_PATH"
  open "$INSTALL_PATH"
  echo "✔ Installed to $INSTALL_PATH and relaunched"
fi

# ── Create DMG ────────────────────────────────────────────────────────────────
mkdir -p "$DIST_DIR"
DMG_PATH="$DIST_DIR/${APP_NAME}-v${VERSION}.dmg"
rm -f "$DMG_PATH"

STAGING="$BUILD_DIR/dmg_staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -sf /Applications "$STAGING/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  -quiet \
  "$DMG_PATH"

rm -rf "$STAGING"

echo "✔ DMG created"
echo ""
echo "┌──────────────────────────────────────────────────────────┐"
echo "│  Output"
echo "│  App : $APP_BUNDLE"
echo "│  DMG : $DMG_PATH"
echo "├──────────────────────────────────────────────────────────┤"
echo "│  Other Macs: open the DMG and drag to Applications,"
echo "│  then right-click → Open on first launch (app is unsigned)."
echo "└──────────────────────────────────────────────────────────┘"
