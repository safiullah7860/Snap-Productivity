#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/Snap-Productivity.app"
VERSION="${1:-1.0.6}"
DIST="$ROOT/dist"
STAGE="$DIST/Snap-Productivity"
ZIP="$DIST/Snap-Productivity-${VERSION}.zip"
DMG="$DIST/Snap-Productivity-${VERSION}.dmg"

SIGNING_IDENTITY="${APPLE_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development:/ {print $2; exit}')"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "ERROR: No Apple Development signing identity was found."
  echo "Run: security find-identity -v -p codesigning"
  exit 1
fi

echo "=== Snap-Productivity Release Builder ==="
echo "Version: ${VERSION}"
echo "Signing: ${SIGNING_IDENTITY}"
echo
echo "[1/5] Building and signing the app..."
APPLE_SIGNING_IDENTITY="$SIGNING_IDENTITY" "$ROOT/install.sh"

echo
echo "[2/5] Verifying the signed app..."
codesign --verify --deep --strict --verbose=2 "$APP"
echo
codesign --display --verbose=2 "$APP" 2>&1 | grep -E '^(Executable|Identifier|Format|Authority|TeamIdentifier|Signature=|Timestamp=)' || true

echo
echo "[3/5] Preparing release folder..."
rm -rf "$DIST"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Snap-Productivity.app"

# Include a simple Applications shortcut for the DMG.
ln -s /Applications "$STAGE/Applications"

echo
echo "[4/5] Creating ZIP and DMG..."
# ZIP preserves the signed .app exactly; do not re-sign it after this point.
ditto -c -k --keepParent "$STAGE/Snap-Productivity.app" "$ZIP"

hdiutil create \
  -volname "Snap-Productivity ${VERSION}" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

rm -rf "$STAGE"

echo
echo "[5/5] Final verification..."
unzip -q -t "$ZIP"

echo
echo "========================================"
echo "RELEASE READY"
echo "========================================"
echo
echo "ZIP:"
echo "$ZIP"
echo
echo "DMG:"
echo "$DMG"
echo
echo "Upload the ZIP or DMG to the GitHub Release."
echo
