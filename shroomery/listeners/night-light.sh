#!/usr/bin/env bash
# Night-light schedule (settings/night-light.json): every minute asks
# hyprsunset.sh what the schedule wants and switches only when that changes
# (lib.sh night_light_action), so a manual toggle holds until the next on/off
# time. The first pass, and the first after a suspend, apply the schedule.
source "$HOME/.config/shroomery/lib.sh"

script="$SHROOMERY_SCRIPTS/hyprsunset.sh"
last=""
last_run=$(date +%s)

while true; do
    now=$(date +%s)
    wanted=$("$script" wanted)
    action=$(night_light_action "$last" "$wanted" $(( now - last_run )))
    [ -n "$action" ] && "$script" "$action"
    last=$wanted
    last_run=$now
    sleep 60
done
