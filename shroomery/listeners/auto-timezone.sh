#!/usr/bin/env bash
# Automatic timezone (settings/time.json autoTimezone): runs
# `time.sh auto-timezone` once at start and whenever NetworkManager reports
# full connectivity again (a new network, waking up somewhere else). Does
# nothing while autoTimezone is off. Needs nmcli; exits quietly without it.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

script="$SHROOMERY_SCRIPTS/time.sh"

check() {
    [ "$(time_setting autoTimezone)" = true ] && "$script" auto-timezone >/dev/null 2>&1
    return 0
}

command -v nmcli >/dev/null 2>&1 || exit 0

check
while true; do
    nmcli monitor 2>/dev/null | while IFS= read -r line; do
        case $line in
            *"Connectivity is now 'full'"*) check ;;
        esac
    done
    sleep 5
done
