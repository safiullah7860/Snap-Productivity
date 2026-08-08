#!/bin/bash
set -u
APP="$HOME/Applications/SnapReplacement.app"
LOG="$HOME/Library/Logs/SnapReplacement.log"
echo "== SnapReplacement 1.4.1 diagnostics =="
echo
echo "[1] Bundle"
if [ -d "$APP" ]; then echo "Bundle: OK"; else echo "Bundle: MISSING"; fi
file "$APP/Contents/MacOS/SnapReplacement" 2>/dev/null || true
codesign -dvvv "$APP" 2>&1 | grep -E 'Identifier=|TeamIdentifier=|Format=' || true
echo
echo "[2] Process"
pgrep -fl "$APP/Contents/MacOS/SnapReplacement" || echo "Process: NOT RUNNING"
echo
echo "[3] Recent diagnostic log"
if [ -f "$LOG" ]; then tail -40 "$LOG"; else echo "Log missing: $LOG"; fi
echo
echo "Done."
