#!/usr/bin/env bash
# Tests for the input helpers in lib.sh. Run: bash tests/input.sh
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

fails=0
check() {  # check NAME EXPECTED ACTUAL
    if [ "$2" != "$3" ]; then
        echo "FAIL $1: expected '$2', got '$3'"
        fails=$((fails + 1))
    fi
}

# clamp_decimal
check "decimal in range" 0.300 "$(clamp_decimal 0.3 0.05 4 1)"
check "decimal low" 0.050 "$(clamp_decimal 0.01 0.05 4 1)"
check "decimal high" 4.000 "$(clamp_decimal 9 0.05 4 1)"
check "decimal junk" 1 "$(clamp_decimal abc 0.05 4 1)"
check "decimal empty" 1 "$(clamp_decimal "" 0.05 4 1)"
check "decimal comma" 1 "$(clamp_decimal "0,3" 0.05 4 1)"
# A comma-decimal locale must not change the output.
check "decimal et_EE" 0.300 "$(LC_NUMERIC=et_EE.UTF-8 clamp_decimal 0.3 0.05 4 1)"

# monitor_speed_factor: logical height / 1080
check "1080p@1" 1.000 "$(monitor_speed_factor 1920 1080 1 0)"
check "4k@1.5" 1.333 "$(monitor_speed_factor 3840 2160 1.5 0)"
check "4k@1" 2.000 "$(monitor_speed_factor 3840 2160 1 0)"
check "4k@2" 1.000 "$(monitor_speed_factor 3840 2160 2 0)"
check "1440p@1" 1.333 "$(monitor_speed_factor 2560 1440 1 0)"
check "rotated 1080p" 1.778 "$(monitor_speed_factor 1920 1080 1 1)"
check "flipped 1080p" 1.000 "$(monitor_speed_factor 1920 1080 1 4)"
check "rotated flipped" 1.778 "$(monitor_speed_factor 1920 1080 1 7)"
check "no monitor" 1.000 "$(monitor_speed_factor 0 0 1 0)"
check "junk" 1.000 "$(monitor_speed_factor abc 1080 1 0)"
check "missing transform" 2.000 "$(monitor_speed_factor 3840 2160 1)"

# effective_speed
check "speed × factor" 0.400 "$(effective_speed 0.3 1.333)"
check "speed × 2" 0.600 "$(effective_speed 0.3 2.000)"
check "speed max" 10.000 "$(effective_speed 4 3)"
check "speed min" 0.050 "$(effective_speed 0.05 0.5)"

check "accel profile" "custom 1 0 0.400" "$(flat_accel_profile 0.400)"

# input_setting
tmp=$(mktemp -d)
INPUT_SETTINGS="$tmp/input.json"
check "default layout" us "$(input_setting layout)"
check "default variant" "" "$(input_setting variant)"
check "default speed" 1.000 "$(input_setting speed)"
check "default scale" false "$(input_setting scaleWithMonitor)"

echo '{"layout":"ee","variant":"nodeadkeys","speed":0.3,"scaleWithMonitor":true}' > "$INPUT_SETTINGS"
check "layout" ee "$(input_setting layout)"
check "variant" nodeadkeys "$(input_setting variant)"
check "speed" 0.300 "$(input_setting speed)"
check "scale" true "$(input_setting scaleWithMonitor)"

echo '{"layout":"ee\"; os.execute(\"x","variant":"a b","speed":"fast","scaleWithMonitor":"yes"}' > "$INPUT_SETTINGS"
check "bad layout" us "$(input_setting layout)"
check "bad variant" "" "$(input_setting variant)"
check "bad speed" 1.000 "$(input_setting speed)"
check "bad scale" false "$(input_setting scaleWithMonitor)"

echo '{"speed":99}' > "$INPUT_SETTINGS"
check "speed clamped" 4.000 "$(input_setting speed)"

echo 'not json' > "$INPUT_SETTINGS"
check "bad json" us "$(input_setting layout)"
rm -rf "$tmp"

if (( fails )); then
    echo "$fails failed"
    exit 1
fi
echo "all passed"
