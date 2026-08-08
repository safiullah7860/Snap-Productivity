#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/Snap-Productivity.app"
BUILD="$ROOT/.build"
LOG="$HOME/Library/Logs/Snap-Productivity.log"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"
LIPO="$(xcrun --find lipo)"

case "$(uname -m)" in
  arm64|x86_64) ;;
  *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

echo "[1/6] Cleaning old running copy..."
killall SnapProductivity 2>/dev/null || true

echo "[2/6] Compiling native universal binary..."
rm -rf "$BUILD"
mkdir -p "$BUILD/arm64" "$BUILD/x86_64"

"$SWIFTC" -target "arm64-apple-macos13.0" -sdk "$SDK" -O \
  -framework AppKit -framework ApplicationServices -framework CoreGraphics -framework ServiceManagement \
  "$ROOT/SnapProductivity.swift" -o "$BUILD/arm64/SnapProductivity"

"$SWIFTC" -target "x86_64-apple-macos13.0" -sdk "$SDK" -O \
  -framework AppKit -framework ApplicationServices -framework CoreGraphics -framework ServiceManagement \
  "$ROOT/SnapProductivity.swift" -o "$BUILD/x86_64/SnapProductivity"

"$LIPO" -create "$BUILD/arm64/SnapProductivity" "$BUILD/x86_64/SnapProductivity" \
  -output "$BUILD/SnapProductivity"

echo "[3/6] Installing application bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$BUILD/SnapProductivity" "$APP/Contents/MacOS/SnapProductivity"
chmod 755 "$APP/Contents/MacOS/SnapProductivity"

echo "[4/6] Ad-hoc signing and clearing quarantine..."
codesign --force --deep --sign - "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "[5/6] Verifying installation..."
test -x "$APP/Contents/MacOS/SnapProductivity"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"

mkdir -p "$(dirname "$LOG")"
: > "$LOG"

echo "[6/6] Starting directly (avoids Finder Gatekeeper launch path)..."
nohup "$APP/Contents/MacOS/SnapProductivity" >/dev/null 2>&1 &
sleep 2

echo
echo "SUCCESS"
echo "App: $APP"
echo "Log: $LOG"
echo
echo "FIRST RUN:"
echo "1. Enable Snap-Productivity in Accessibility."
echo "2. Enable Snap-Productivity in Input Monitoring."
echo "3. Quit and relaunch it once."
echo "4. Confirm it appears under General -> Login Items & Extensions."
echo
echo "This build uses Accessibility window raising after activation to handle apps whose process becomes active while their window remains hidden."
