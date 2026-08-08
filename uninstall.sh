#!/bin/bash
set -euo pipefail
killall SnapProductivity 2>/dev/null || true
rm -rf "$HOME/Applications/Snap-Productivity.app"
rm -f "$HOME/Library/LaunchAgents/com.safibaig.SnapProductivity.plist"
tccutil reset Accessibility com.safibaig.SnapProductivity >/dev/null 2>&1 || true
tccutil reset ListenEvent com.safibaig.SnapProductivity >/dev/null 2>&1 || true
echo "Snap-Productivity removed."
