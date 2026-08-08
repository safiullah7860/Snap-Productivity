#!/bin/bash
set -u
APP="$HOME/Applications/Snap-Productivity.app"
LOG="$HOME/Library/Logs/Snap-Productivity.log"
echo "== Snap-Productivity 1.0.4 diagnostics =="
echo
echo "[1] Bundle"
if [ -d "$APP" ]; then echo "Bundle: OK"; else echo "Bundle: MISSING"; fi
file "$APP/Contents/MacOS/SnapProductivity" 2>/dev/null || true
codesign -dvvv "$APP" 2>&1 | grep -E 'Identifier=|TeamIdentifier=|Format=|Version=' || true
echo
echo "[2] Process"
pgrep -fl "$APP/Contents/MacOS/SnapProductivity" || echo "Process: NOT RUNNING"
echo
echo "[3] Permissions"
echo "Accessibility: $(python3 - <<'PY' 2>/dev/null || true
# Intentionally not probing TCC; see log below.
print('check System Settings if shortcuts are unavailable')
PY
)"
echo
echo "[4] Log"
if [ -f "$LOG" ]; then tail -80 "$LOG"; else echo "Log missing: $LOG"; fi
echo
echo "[5] Login Item status (if available)"
if command -v sfltool >/dev/null 2>&1; then
  sfltool dumpbtm 2>/dev/null | grep -A8 -B2 -i 'Snap-Productivity' || echo "No matching Login Item entry found."
fi
echo
echo "Done."
