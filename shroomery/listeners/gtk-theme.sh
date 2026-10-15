#!/usr/bin/env bash
# Re-theme (matugen + GTK) whenever the GTK dark/light preference changes.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

if ! command -v inotifywait &> /dev/null; then
    error "inotifywait is not installed (inotify-tools)."
    exit 1
fi

settings_dir=$(dirname "$GTK3_SETTINGS_FILE")
settings_name=$(basename "$GTK3_SETTINGS_FILE")
last_mode=$(current_mode)

inotifywait -m -q -e close_write,moved_to "$settings_dir" | while read -r _dir _events filename; do
    [ "$filename" = "$settings_name" ] || continue
    mode=$(current_mode)
    # settings.ini is also rewritten for unrelated keys; only react to a mode flip.
    [ "$mode" = "$last_mode" ] && continue
    last_mode="$mode"
    info "GTK switched to $mode, re-applying theme"
    "$SHROOMERY_SCRIPTS/apply-theme.sh" --reapply
    "$HOME/.config/hypr/scripts/gtk.sh" &
done
