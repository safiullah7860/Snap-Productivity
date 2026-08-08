#!/bin/bash
set -euo pipefail
killall SnapProductivity 2>/dev/null || true
rm -rf "$HOME/Applications/Snap-Productivity.app"
# Remove the local login-agent fallback if an older build created one.
rm -f "$HOME/Library/LaunchAgents/com.safibaig.SnapProductivity.plist"
# Remove old app permissions without touching other applications.
tccutil reset Accessibility com.safibaig.SnapProductivity >/dev/null 2>&1 || true
tccutil reset ListenEvent com.safibaig.SnapProductivity >/dev/null 2>&1 || true
echo "Snap-Productivity removed."
