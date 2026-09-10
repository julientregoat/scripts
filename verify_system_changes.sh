#!/usr/bin/env bash
# Verify that every change recorded in SYSTEM-CHANGES.md is still in effect.
# Some of these can revert on their own (an app update reinstalling a LaunchAgent),
# so run this when a previously-fixed symptom reappears.
#
# Exits 0 if all checks pass, 1 if anything has drifted.

set -uo pipefail

drift=0

pass() { printf '  \033[32mOK\033[0m    %s\n' "$1"; }
fail() { printf '  \033[31mDRIFT\033[0m %s\n' "$1"; drift=1; }

echo "2026-09-07 — Logitech G HUB autostart disabled"

if launchctl list | grep -q 'com\.logi\.ghub$'; then
    fail "com.logi.ghub is registered with launchctl (expected: absent)"
else
    pass "com.logi.ghub not registered with launchctl"
fi

if [ -f /Library/LaunchAgents/com.logi.ghub.plist ]; then
    fail "com.logi.ghub.plist is back in /Library/LaunchAgents — a G HUB update likely reinstalled it"
elif [ -f /Library/LaunchAgents/com.logi.ghub.plist.disabled ]; then
    pass "com.logi.ghub.plist.disabled present, active plist absent"
else
    fail "neither com.logi.ghub.plist nor .disabled found — G HUB may have been uninstalled/moved"
fi

if pgrep -q -f lghub_system_tray; then
    fail "lghub_system_tray is running — this is the process that steals focus"
else
    pass "lghub_system_tray not running"
fi

echo
if [ "$drift" -eq 0 ]; then
    echo "All system changes still in effect."
else
    echo "Drift detected. See SYSTEM-CHANGES.md for what each change was and how to reapply it."
fi

exit "$drift"
