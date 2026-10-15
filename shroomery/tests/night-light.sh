#!/usr/bin/env bash
# Tests for the night-light helpers in lib.sh. Run: bash tests/night-light.sh
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

fails=0
check() {  # check NAME EXPECTED ACTUAL
    if [ "$2" != "$3" ]; then
        echo "FAIL $1: expected '$2', got '$3'"
        fails=$((fails + 1))
    fi
}
in_window() { time_in_window "$@" && echo in || echo out; }

# time_to_minutes
check "00:00" 0 "$(time_to_minutes 00:00)"
check "07:05" 425 "$(time_to_minutes 07:05)"
check "7:05" 425 "$(time_to_minutes 7:05)"
check "23:59" 1439 "$(time_to_minutes 23:59)"
check "24:00 rejected" "" "$(time_to_minutes 24:00)"
check "7:5 rejected" "" "$(time_to_minutes 7:5)"
check "abc rejected" "" "$(time_to_minutes abc)"
time_to_minutes 12:60 >/dev/null; check "12:60 exit" 1 "$?"

# time_in_window: 09:00–17:00
check "day before" out "$(in_window 539 540 1020)"
check "day start" in "$(in_window 540 540 1020)"
check "day end" out "$(in_window 1020 540 1020)"
# 21:00–07:00 crosses midnight
check "night 23:30" in "$(in_window 1410 1260 420)"
check "night 00:00" in "$(in_window 0 1260 420)"
check "night 06:59" in "$(in_window 419 1260 420)"
check "night 07:00" out "$(in_window 420 1260 420)"
check "night 20:59" out "$(in_window 1259 1260 420)"
check "night 21:00" in "$(in_window 1260 1260 420)"
# empty window
check "start == end" out "$(in_window 600 600 600)"

# clamp_int
check "clamp in range" 4500 "$(clamp_int 4500 2500 6500 4500)"
check "clamp low" 2500 "$(clamp_int 1000 2500 6500 4500)"
check "clamp high" 6500 "$(clamp_int 9000 2500 6500 4500)"
check "clamp string" 3000 "$(clamp_int "3000" 2500 6500 4500)"
check "clamp float" 80 "$(clamp_int 80.4 50 100 100)"
check "clamp junk" 4500 "$(clamp_int abc 2500 6500 4500)"
check "clamp empty" 100 "$(clamp_int "" 50 100 100)"
check "clamp bool" 100 "$(clamp_int true 50 100 100)"

# night_light_setting
tmp=$(mktemp -d)
NIGHT_LIGHT_SETTINGS="$tmp/night-light.json"

# missing file → defaults
check "default mode" off "$(night_light_setting mode)"
check "default on" 21:00 "$(night_light_setting on)"
check "default off" 07:00 "$(night_light_setting off)"
check "default temperature" 4500 "$(night_light_setting temperature)"
check "default gamma" 100 "$(night_light_setting gamma)"

echo '{"mode":"sun","on":"7:30","off":"6:00","temperature":3200,"gamma":"80"}' > "$NIGHT_LIGHT_SETTINGS"
check "mode" sun "$(night_light_setting mode)"
check "on padded" 07:30 "$(night_light_setting on)"
check "off padded" 06:00 "$(night_light_setting off)"
check "temperature" 3200 "$(night_light_setting temperature)"
check "gamma string" 80 "$(night_light_setting gamma)"

echo '{"mode":"party","on":"25:00","temperature":99999,"gamma":true}' > "$NIGHT_LIGHT_SETTINGS"
check "bad mode" off "$(night_light_setting mode)"
check "bad on" 21:00 "$(night_light_setting on)"
check "missing off" 07:00 "$(night_light_setting off)"
check "temperature clamped" 6500 "$(night_light_setting temperature)"
check "gamma bool" 100 "$(night_light_setting gamma)"

echo 'not json {' > "$NIGHT_LIGHT_SETTINGS"
check "corrupt mode" off "$(night_light_setting mode)"
check "corrupt temperature" 4500 "$(night_light_setting temperature)"

rm -rf "$tmp"

# night_light_action LAST WANTED GAP: what the listener does this pass
check "first pass applies" on "$(night_light_action "" on 0)"
check "no change, no action" "" "$(night_light_action on on 60)"
check "change acts" off "$(night_light_action on off 60)"
check "no schedule" "" "$(night_light_action off none 60)"
check "resume after suspend re-applies" on "$(night_light_action on on 3600)"
check "short gap keeps manual override" "" "$(night_light_action on on 179)"

if [ "$fails" -gt 0 ]; then
    echo "$fails failed"
    exit 1
fi
echo "all passed"
