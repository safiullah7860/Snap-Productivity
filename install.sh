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

echo "[1/5] Compiling native executables..."
mkdir -p "$BUILD/arm64" "$BUILD/x86_64"

"$SWIFTC" -target "arm64-apple-macos13.0" -sdk "$SDK" -O \
  -framework AppKit -framework ApplicationServices -framework CoreGraphics -framework ServiceManagement \
  "$ROOT/SnapProductivity.swift" -o "$BUILD/arm64/SnapProductivity"

"$SWIFTC" -target "x86_64-apple-macos13.0" -sdk "$SDK" -O \
  -framework AppKit -framework ApplicationServices -framework CoreGraphics -framework ServiceManagement \
  "$ROOT/SnapProductivity.swift" -o "$BUILD/x86_64/SnapProductivity"

"$LIPO" -create "$BUILD/arm64/SnapProductivity" "$BUILD/x86_64/SnapProductivity" \
  -output "$BUILD/SnapProductivity"

echo "[2/5] Creating application bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$BUILD/SnapProductivity" "$APP/Contents/MacOS/SnapProductivity"
chmod 755 "$APP/Contents/MacOS/SnapProductivity"

echo "[3/5] Signing and clearing quarantine..."
codesign --force --deep --sign - "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "[4/5] Verifying..."
test -x "$APP/Contents/MacOS/SnapProductivity"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
file "$APP/Contents/MacOS/SnapProductivity"

echo "[5/5] Launching..."
killall SnapProductivity 2>/dev/null || true
: > "$LOG"
open "$APP"
sleep 2

echo
echo "SUCCESS"
echo "App: $APP"
echo "Log: $LOG"
echo
echo "NEXT — first run only:"
echo "  1. System Settings -> Privacy & Security -> Accessibility -> add/enable Snap-Productivity."
echo "  2. System Settings -> Privacy & Security -> Input Monitoring -> add/enable Snap-Productivity."
echo "  3. Quit and reopen Snap-Productivity."
echo "  4. Confirm it appears under System Settings -> General -> Login Items & Extensions."
echo
echo "After that, it should start automatically at login."
