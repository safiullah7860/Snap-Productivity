#!/bin/bash
set -euo pipefail
killall SnapProductivity 2>/dev/null || true
rm -rf "$HOME/Applications/Snap-Productivity.app"
rm -f "$HOME/Library/LaunchAgents/com.safibaig.SnapProductivity.plist"
rm -f "$HOME/Library/Logs/Snap-Productivity.log"
echo "Snap-Productivity removed."
