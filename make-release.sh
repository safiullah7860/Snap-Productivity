#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/Snap-Productivity.app"
VERSION="${1:-1.0.5}"
DIST="$ROOT/dist"
ZIP="$DIST/Snap-Productivity-${VERSION}.zip"

echo "Building Snap-Productivity ${VERSION}..."
"$ROOT/install.sh"

echo "Preparing release..."
rm -rf "$DIST"
mkdir -p "$DIST"

# Copy the installed app into the release directory.
cp -R "$APP" "$DIST/Snap-Productivity.app"

# Make sure the release copy is ad-hoc signed and verified.
codesign --force --deep --sign - "$DIST/Snap-Productivity.app"
codesign --verify --deep --strict "$DIST/Snap-Productivity.app"

echo "Creating ZIP..."
ditto -c -k --keepParent "$DIST/Snap-Productivity.app" "$ZIP"

rm -rf "$DIST/Snap-Productivity.app"

echo
echo "Release ready:"
echo "$ZIP"
echo
echo "Upload this ZIP to your GitHub Release."
