#!/bin/bash
set -euo pipefail
killall SnapReplacement 2>/dev/null || true
rm -rf "$HOME/Applications/SnapReplacement.app"
tccutil reset Accessibility com.safibaig.SnapReplacement >/dev/null 2>&1 || true
tccutil reset ListenEvent com.safibaig.SnapReplacement >/dev/null 2>&1 || true
tccutil reset Accessibility com.safibaig.SnapReplacement141 >/dev/null 2>&1 || true
tccutil reset ListenEvent com.safibaig.SnapReplacement141 >/dev/null 2>&1 || true
echo "SnapReplacement removed."
