#!/usr/bin/env bash
# Tests for the date/time/locale helpers in lib.sh. Run: bash tests/time.sh
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

fails=0
check() {  # check NAME EXPECTED ACTUAL
    if [ "$2" != "$3" ]; then
        echo "FAIL $1: expected '$2', got '$3'"
        fails=$((fails + 1))
    fi
}
ok() { "$@" && echo yes || echo no; }

# valid_datetime
check "date time" yes "$(ok valid_datetime "2026-11-07 12:30")"
check "with seconds" yes "$(ok valid_datetime "2026-11-07 12:30:59")"
check "leap day" yes "$(ok valid_datetime "2028-02-29 00:00")"
check "no leap day" no "$(ok valid_datetime "2026-02-29 00:00")"
check "feb 30" no "$(ok valid_datetime "2026-02-30 10:00")"
check "month 13" no "$(ok valid_datetime "2026-13-01 10:00")"
check "hour 24" no "$(ok valid_datetime "2026-11-07 24:00")"
check "minute 60" no "$(ok valid_datetime "2026-11-07 12:60")"
check "no time" no "$(ok valid_datetime "2026-11-07")"
check "injection" no "$(ok valid_datetime "2026-11-07 12:30; rm -rf ~")"
check "empty" no "$(ok valid_datetime "")"

# valid_locale_assignment
check "LANG" yes "$(ok valid_locale_assignment LANG=en_US.UTF-8)"
check "LC_TIME" yes "$(ok valid_locale_assignment LC_TIME=et_EE.UTF-8)"
check "modifier" yes "$(ok valid_locale_assignment LC_TIME=sr_RS@latin)"
check "C.UTF-8" yes "$(ok valid_locale_assignment LC_COLLATE=C.UTF-8)"
check "unknown var" no "$(ok valid_locale_assignment FOO=en_US.UTF-8)"
check "empty value" no "$(ok valid_locale_assignment LANG=)"
check "no =" no "$(ok valid_locale_assignment LANG)"
check "space" no "$(ok valid_locale_assignment "LANG=en US")"
check "quote" no "$(ok valid_locale_assignment 'LANG=en"US')"

# normalize_locale_name: as locale -a prints it
check "utf8" en_US.utf8 "$(normalize_locale_name en_US.UTF-8)"
check "already" et_EE.utf8 "$(normalize_locale_name et_EE.utf8)"
check "iso" de_DE.iso88591 "$(normalize_locale_name de_DE.ISO-8859-1)"
check "modifier" sr_RS@latin "$(normalize_locale_name sr_RS@latin)"
check "codeset+modifier" ca_ES.utf8@valencia "$(normalize_locale_name ca_ES.UTF-8@valencia)"

# time_setting
tmp=$(mktemp -d)
TIME_SETTINGS="$tmp/time.json"
check "default auto" false "$(time_setting autoTimezone)"
echo '{"autoTimezone":true}' > "$TIME_SETTINGS"
check "auto on" true "$(time_setting autoTimezone)"
echo '{"autoTimezone":"true"}' > "$TIME_SETTINGS"
check "auto string" true "$(time_setting autoTimezone)"
echo '{"autoTimezone":1}' > "$TIME_SETTINGS"
check "auto junk" false "$(time_setting autoTimezone)"
echo 'nope' > "$TIME_SETTINGS"
check "bad json" false "$(time_setting autoTimezone)"
rm -rf "$tmp"

# clock_is_24h (statusbar.json clock.format)
tmp=$(mktemp -d)
STATUSBAR_SETTINGS="$tmp/statusbar.json"
check "no file → 24h" yes "$(ok clock_is_24h)"
echo '{"bar":{"enabled":true}}' > "$STATUSBAR_SETTINGS"
check "no clock → 24h" yes "$(ok clock_is_24h)"
echo '{"clock":{"format":"HH:mm:ss"}}' > "$STATUSBAR_SETTINGS"
check "HH:mm:ss" yes "$(ok clock_is_24h)"
echo '{"clock":{"format":"h:mm AP"}}' > "$STATUSBAR_SETTINGS"
check "h:mm AP" no "$(ok clock_is_24h)"
echo '{"clock":{"format":"h:mm:ss ap"}}' > "$STATUSBAR_SETTINGS"
check "h:mm:ss ap" no "$(ok clock_is_24h)"
echo "{\"clock\":{\"format\":\"HH:mm 'at'\"}}" > "$STATUSBAR_SETTINGS"
check "quoted a ignored" yes "$(ok clock_is_24h)"
echo 'not json' > "$STATUSBAR_SETTINGS"
check "bad json → 24h" yes "$(ok clock_is_24h)"
rm -rf "$tmp"

if (( fails )); then
    echo "$fails failed"
    exit 1
fi
echo "all passed"
