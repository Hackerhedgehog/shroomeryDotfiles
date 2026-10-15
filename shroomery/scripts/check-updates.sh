#!/usr/bin/env bash
# Print the pending package update count as JSON
# ({"text": N, "alt": N, "tooltip": ..., "class": green|yellow|red}).
# Prints nothing when there are no updates. Read by StatusbarApp/UpdatesModule.qml.

has() { command -v "$1" &> /dev/null; }

# Serialize parallel checks (one per statusbar) so they don't race on the
# package databases.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/shroomery-check-updates.lock"
flock 9

threshold_yellow=25
threshold_red=100

if has pacman; then
    while [ -f /var/lib/pacman/db.lck ] || [ -f "${TMPDIR:-/tmp}/checkup-db-${UID}/db.lck" ]; do
        sleep 1
    done
    aur_helper="yay"
    if ! has yay && has paru; then
        aur_helper="paru"
    fi
    updates_aur=$($aur_helper -Qum 2>/dev/null | wc -l)
    updates_pacman=$(checkupdates 2>/dev/null | wc -l)
    updates=$((updates_aur + updates_pacman))
elif has dnf; then
    updates=$(dnf check-update -q | grep -c '^[a-z0-9]')
else
    updates=0
fi

css_class="green"
[ "$updates" -gt $threshold_yellow ] && css_class="yellow"
[ "$updates" -gt $threshold_red ] && css_class="red"

if [ "$updates" -gt 0 ]; then
    printf '{"text": "%s", "alt": "%s", "tooltip": "Click to update your system", "class": "%s"}' \
        "$updates" "$updates" "$css_class"
fi
