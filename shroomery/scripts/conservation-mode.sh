#!/usr/bin/env bash
# Battery conservation mode (Lenovo ideapad_acpi / Legion: stops charging at
# about 60-80%, the firmware decides).
#
# Usage: conservation-mode.sh status
#          Prints available=true|false (the driver exposes the switch) and
#          enabled=true|false.
#        conservation-mode.sh on|off|toggle
#          Writes the sysfs file as root (asks for the password through pkexec).
# Exit 1 = bad arguments / not supported, 2 = not authorized / cancelled, 3 = write failed.

FILE=$(compgen -G "/sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode" | head -n1)

enabled() { [ "$(cat "$FILE" 2>/dev/null)" = 1 ]; }

case "${1:-}" in
    status)
        if [ -n "$FILE" ]; then echo "available=true"; else echo "available=false"; fi
        if [ -n "$FILE" ] && enabled; then echo "enabled=true"; else echo "enabled=false"; fi
        ;;
    on | off | toggle)
        [ -n "$FILE" ] || { echo "conservation mode is not supported on this machine" >&2; exit 1; }
        value=0
        case "$1" in
            on) value=1 ;;
            toggle) enabled || value=1 ;;
        esac
        if [ "$(id -u)" -ne 0 ]; then
            pkexec "$(readlink -f "$0")" "$([ "$value" = 1 ] && echo on || echo off)"
            code=$?
            # 126/127: the password dialog was dismissed or auth failed.
            [ "$code" -eq 126 ] || [ "$code" -eq 127 ] && exit 2
            exit "$code"
        fi
        echo "$value" > "$FILE" || exit 3
        ;;
    *)
        sed -n '2,10s/^# \{0,1\}//p' "$0"
        exit 1
        ;;
esac
