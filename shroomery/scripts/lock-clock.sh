#!/usr/bin/env bash
# The lock screen clock (hypr/hyprlock.conf runs it every second): the time
# now, 24-hour or 12-hour like the shell's clock (TimeApp → Clock format →
# 24-hour clock; lib.sh clock_is_24h). AM/PM in English: et_EE and other
# locales have no AM/PM text, so %p would be empty.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

if clock_is_24h; then
    date +%H:%M
else
    LC_TIME=C date '+%-I:%M %p'
fi
