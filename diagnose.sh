#!/bin/bash
set -euo pipefail
APP="$HOME/Applications/Snap-Productivity.app"
echo "Snap-Productivity diagnostics"
echo "App: $APP"
if [ -x "$APP/Contents/MacOS/SnapProductivity" ]; then echo "App executable: OK"; else echo "App executable: MISSING"; fi
if pgrep -x SnapProductivity >/dev/null 2>&1; then echo "Process: RUNNING ($(pgrep -x SnapProductivity | head -1))"; else echo "Process: NOT RUNNING"; fi
if [ -f "$HOME/Library/Logs/Snap-Productivity.log" ]; then tail -20 "$HOME/Library/Logs/Snap-Productivity.log"; else echo "Log: MISSING"; fi
