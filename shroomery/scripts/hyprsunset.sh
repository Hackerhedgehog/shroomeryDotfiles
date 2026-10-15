#!/usr/bin/env bash
# Night light (hyprsunset) with the strength and schedule in
# settings/night-light.json (written by the quickshell settings panel).
# Usage: hyprsunset.sh [COMMAND]
#   toggle     on when off, off when on (default; SUPER+SHIFT+H)
#   on | off   start / stop hyprsunset
#   status     print on or off
#   apply      re-apply temperature and gamma while running (no restart)
#   sync       switch on/off to match the schedule now
#   wanted     print what the schedule wants now: on, off, or none (no schedule)
#   sun-times  print "SUNRISE SUNSET" (HH:MM), fetched from wttr.in once a day
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

# Last wttr.in attempt; no new attempt within 30 minutes (offline, wttr down).
SUN_TIMES_ATTEMPT="$SHROOMERY_RUNTIME/sun-times-attempt"

running() { pgrep -x hyprsunset >/dev/null; }

start() {
    running && return 0
    if ! command -v hyprsunset >/dev/null 2>&1; then
        error "hyprsunset is not installed"
        exit 2
    fi
    setsid hyprsunset -t "$(night_light_setting temperature)" \
        -g "$(night_light_setting gamma)" >/dev/null 2>&1 &
}

stop() {
    pkill -x hyprsunset
    return 0
}

# Errors are ignored: right after a start the socket may not be up yet, and
# the values were passed on start anyway.
apply() {
    running || return 0
    hyprctl hyprsunset temperature "$(night_light_setting temperature)" >/dev/null 2>&1
    hyprctl hyprsunset gamma "$(night_light_setting gamma)" >/dev/null 2>&1
    return 0
}

recent_attempt() {
    [ -n "$(find "$SUN_TIMES_ATTEMPT" -mmin -30 2>/dev/null)" ]
}

# Today's sun times from the cache, refreshed from wttr.in (same location as
# the dashboard weather) when they're not from today. A failed fetch keeps
# the old times; exit 1 when none are known at all.
sun_times() {
    local today date="" sunrise="" sunset="" loc out
    today=$(date +%F)
    [ -f "$SUN_TIMES_FILE" ] && read -r date sunrise sunset < "$SUN_TIMES_FILE"
    if [ "$date" != "$today" ] && ! recent_attempt; then
        mkdir -p "$SHROOMERY_RUNTIME" "$SHROOMERY_CACHE"
        touch "$SUN_TIMES_ATTEMPT"
        loc=$(jq -rn --arg s "$(setting weather-location "")" '$s | @uri')
        out=$(curl -sf --max-time 10 "https://wttr.in/${loc}?format=%S+%s")
        if [[ "$out" =~ ^([0-9]{2}:[0-9]{2}):[0-9]{2}\ ([0-9]{2}:[0-9]{2}):[0-9]{2}$ ]]; then
            sunrise=${BASH_REMATCH[1]}
            sunset=${BASH_REMATCH[2]}
            echo "$today $sunrise $sunset" > "$SUN_TIMES_FILE"
        fi
    fi
    [ -n "$sunrise" ] && [ -n "$sunset" ] || return 1
    echo "$sunrise $sunset"
}

wanted() {
    local mode start end now times
    mode=$(night_light_setting mode)
    if [ "$mode" = off ]; then
        echo none
        return
    fi
    start=$(time_to_minutes "$(night_light_setting on)")
    end=$(time_to_minutes "$(night_light_setting off)")
    if [ "$mode" = sun ] && times=$(sun_times); then
        end=$(time_to_minutes "${times% *}")
        start=$(time_to_minutes "${times#* }")
    fi
    now=$(( 10#$(date +%H) * 60 + 10#$(date +%M) ))
    if time_in_window "$now" "$start" "$end"; then echo on; else echo off; fi
}

case "${1:-toggle}" in
    toggle)
        if running; then
            stop
            info "Night light off"
        else
            start
            info "Night light on"
        fi ;;
    on)        start ;;
    off)       stop ;;
    status)    if running; then echo on; else echo off; fi ;;
    apply)     apply ;;
    sync)
        case $(wanted) in
            on)  start ;;
            off) stop ;;
        esac ;;
    wanted)    wanted ;;
    sun-times) sun_times ;;
    *)
        echo "Usage: $0 [toggle|on|off|status|apply|sync|wanted|sun-times]" >&2
        exit 1 ;;
esac
