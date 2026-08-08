#!/bin/bash
set -u
APP="$HOME/Applications/Snap-Productivity.app"
LOG="$HOME/Library/Logs/Snap-Productivity.log"
echo "== Snap-Productivity diagnostics =="
echo
echo "[1] Bundle"
if [ -d "$APP" ]; then echo "Bundle: OK"; else echo "Bundle: MISSING"; fi
file "$APP/Contents/MacOS/SnapProductivity" 2>/dev/null || true
codesign -dvvv "$APP" 2>&1 | grep -E 'Identifier=|TeamIdentifier=|Format=' || true
echo
echo "[2] Process"
pgrep -fl "$APP/Contents/MacOS/SnapProductivity" || echo "Process: NOT RUNNING"
echo
echo "[3] Log"
if [ -f "$LOG" ]; then tail -50 "$LOG"; else echo "Log missing: $LOG"; fi
echo
echo "[4] Login Item status (if available)"
if command -v sfltool >/dev/null 2>&1; then
  sfltool dumpbtm 2>/dev/null | grep -A8 -B2 -i 'Snap-Productivity' || echo "No matching Login Item entry found in sfltool output."
else
  echo "sfltool not available on this macOS version."
fi
echo
echo "Done."
