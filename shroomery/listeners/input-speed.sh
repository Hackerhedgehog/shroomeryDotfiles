#!/usr/bin/env bash
# Mouse speed per monitor (settings/input.json scaleWithMonitor): runs
# `input.sh speed` when the cursor (or focus) moves to another monitor, a
# monitor comes or goes, or the config reloads (a reload resets the speed to
# the one in input.lua). Reads Hyprland's event socket; reconnects when it
# goes away. With scaleWithMonitor off every monitor gets the same speed, so
# the extra applies are harmless.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

script="$SHROOMERY_SCRIPTS/input.sh"

# Hyprland's event lines ("focusedmon>>DP-3,2") from socket2, one per line.
events() {
    python3 -u -c '
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sys.argv[1])
for line in s.makefile("r", encoding="utf-8", errors="replace"):
    sys.stdout.write(line)
' "$1"
}

while true; do
    sock="${XDG_RUNTIME_DIR:-/run/user/$UID}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket2.sock"
    if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || [ ! -S "$sock" ]; then
        sleep 5
        continue
    fi
    "$script" speed
    last=""
    events "$sock" 2>/dev/null | while IFS= read -r line; do
        case $line in
            "focusedmon>>"*)
                mon=${line#focusedmon>>}
                mon=${mon%%,*}
                [ "$mon" = "$last" ] && continue
                last=$mon
                "$script" speed "$mon" ;;
            "monitoraddedv2>>"*|"monitorremovedv2>>"*|"configreloaded>>"*)
                last=""
                "$script" speed ;;
        esac
    done
    sleep 2
done
