#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/SnapReplacement.app"
BUILD="$ROOT/.build"
LOG="$HOME/Library/Logs/SnapReplacement.log"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"
ARCH="$(uname -m)"

case "$ARCH" in
  arm64|x86_64) ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Remove the old app and clear only its old TCC records.
killall SnapReplacement 2>/dev/null || true
rm -rf "$APP"
tccutil reset Accessibility com.safibaig.SnapReplacement >/dev/null 2>&1 || true
tccutil reset ListenEvent com.safibaig.SnapReplacement >/dev/null 2>&1 || true
tccutil reset Accessibility com.safibaig.SnapReplacement141 >/dev/null 2>&1 || true
tccutil reset ListenEvent com.safibaig.SnapReplacement141 >/dev/null 2>&1 || true

echo "[1/4] Compiling native executables..."
mkdir -p "$BUILD/arm64" "$BUILD/x86_64"

"$SWIFTC" -target "arm64-apple-macos13.0" -sdk "$SDK" -O \
  -framework AppKit -framework ApplicationServices -framework CoreGraphics \
  "$ROOT/SnapReplacement.swift" -o "$BUILD/arm64/SnapReplacement"

"$SWIFTC" -target "x86_64-apple-macos13.0" -sdk "$SDK" -O \
  -framework AppKit -framework ApplicationServices -framework CoreGraphics \
  "$ROOT/SnapReplacement.swift" -o "$BUILD/x86_64/SnapReplacement"

"$(xcrun --find lipo)" -create \
  "$BUILD/arm64/SnapReplacement" \
  "$BUILD/x86_64/SnapReplacement" \
  -output "$BUILD/SnapReplacement"

echo "[2/4] Creating application bundle..."
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$BUILD/SnapReplacement" "$APP/Contents/MacOS/SnapReplacement"
chmod 755 "$APP/Contents/MacOS/SnapReplacement"

echo "[3/4] Signing and clearing quarantine..."
codesign --force --deep --sign - "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "[4/4] Verifying..."
test -x "$APP/Contents/MacOS/SnapReplacement"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"

# Clear the previous diagnostic log, then launch the newly built app.
: > "$LOG"
echo "Launching SnapReplacement..."
open "$APP"
sleep 2

echo
echo "SUCCESS"
echo "App: $APP"
echo "Log: $LOG"
echo

echo "NEXT — do these steps exactly:"
echo "  1. System Settings -> Privacy & Security -> Accessibility."
echo "  2. If SnapReplacement is listed, turn it OFF first."
echo "  3. If it is not listed, click + and add: $APP"
echo "  4. Turn SnapReplacement ON."
echo "  5. Return here and run: $ROOT/diagnose.sh"
echo "  6. If the menu-bar icon is not visible, run: tail -100 \"$LOG\""
echo
