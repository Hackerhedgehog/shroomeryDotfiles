#!/usr/bin/env bash
# Pause an animated wallpaper on battery and play it again on AC
# (animated-wallpaper.sh sync; gamemode.sh calls it for gamemode).
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

on_battery && last=battery || last=ac

# Power-supply uevents also come for every battery level change: act only on a flip.
udevadm monitor --udev --subsystem-match=power_supply | while read -r _; do
    on_battery && now=battery || now=ac
    [ "$now" = "$last" ] && continue
    last="$now"
    info "Power source: $now"
    "$SHROOMERY_SCRIPTS/animated-wallpaper.sh" sync
done
