#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/Snap-Productivity.app"
VERSION="${1:-1.0.5}"
DIST="$ROOT/dist"
STAGE="$DIST/Snap-Productivity"
DMG="$DIST/Snap-Productivity-${VERSION}.dmg"

echo "=== Snap-Productivity Release Builder ==="
echo "Version: ${VERSION}"
echo

echo "[1/4] Building the app..."
"$ROOT/install.sh"

echo
echo "[2/4] Preparing DMG..."
rm -rf "$DIST"
mkdir -p "$STAGE"

# Copy the finished app into the DMG staging area.
cp -R "$APP" "$STAGE/Snap-Productivity.app"

# Add an Applications shortcut for drag-and-drop installation.
ln -s /Applications "$STAGE/Applications"

echo
echo "[3/4] Verifying app signature..."
codesign --force --deep --sign - "$STAGE/Snap-Productivity.app"
codesign --verify --deep --strict "$STAGE/Snap-Productivity.app"

echo
echo "[4/4] Creating DMG..."
hdiutil create \
  -volname "Snap-Productivity ${VERSION}" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

# Remove temporary staging files, leaving only the DMG.
rm -rf "$STAGE"

echo
echo "========================================"
echo "RELEASE READY"
echo "========================================"
echo
echo "DMG:"
echo "$DMG"
echo
echo "Upload this file to your GitHub Release:"
echo "Snap-Productivity-${VERSION}.dmg"
echo