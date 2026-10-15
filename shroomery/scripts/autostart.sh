#!/usr/bin/env bash
# Session startup, run once from hypr/autostart.lua: starts Quickshell (main
# shell + OverviewApp) and restores the wallpaper and its theme.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

AWWW_DAEMON_VERSION="$(awww-daemon --version 2>/dev/null | awk '{ print $2 }')"
AWWW_CACHE_FOLDER="${XDG_CACHE_HOME:-"$HOME/.cache"}/awww/$AWWW_DAEMON_VERSION"

mkdir -p "$SHROOMERY_CACHE"
if [ ! -s "$WALLPAPER_CACHE_FILE" ]; then
    default_wallpaper > "$WALLPAPER_CACHE_FILE"
    info "Wallpaper cache file created"
fi

nm-applet --indicator &

# Quickshell reads its icon theme from QS_ICON_THEME, not from GTK. Hyprland
# normally exports it; fall back to the GTK setting for a manual run.
if [ -z "$QS_ICON_THEME" ] && [ -f "$GTK3_SETTINGS_FILE" ]; then
    ICON_THEME="$(grep 'gtk-icon-theme-name' "$GTK3_SETTINGS_FILE" | sed 's/.*\s*=\s*//')"
    [ -n "$ICON_THEME" ] && export QS_ICON_THEME="$ICON_THEME"
fi
info "Quickshell icon theme: ${QS_ICON_THEME:-<unset>}"

killall qs 2>/dev/null || true
info "Starting Quickshell"
qs &

timeout=15
elapsed=0
until pgrep -x qs >/dev/null 2>&1; do
    sleep 0.2
    elapsed=$((elapsed + 1))
    if [ $elapsed -ge $((timeout * 5)) ]; then
        warn "Quickshell did not start within ${timeout}s"
        break
    fi
done
sleep 0.5

# Theming must run on every start; the awww image set is skipped when awww
# already restored it from its own cache, to avoid a flicker. An animated
# wallpaper is restored by animated-wallpaper.sh from its own state (it plays,
# or shows a still on battery / in gamemode).
current=$(head -n 1 "$WALLPAPER_CACHE_FILE")
if is_animated "$current" && [ -s "$ANIMATED_STATE_FILE" ]; then
    info "Restoring animated wallpaper $current"
    "$SHROOMERY_SCRIPTS/wallpaper.sh" "$current" --skip-wallpaper &
    "$SHROOMERY_SCRIPTS/animated-wallpaper.sh" sync &
elif [[ -z $(find "$AWWW_CACHE_FOLDER" -mindepth 1 -maxdepth 1 -type f -print -quit 2>/dev/null) ]]; then
    info "Restoring wallpaper $current"
    "$SHROOMERY_SCRIPTS/wallpaper.sh" "$current" &
else
    info "awww cache present, applying theming only for $current"
    "$SHROOMERY_SCRIPTS/wallpaper.sh" "$current" --skip-wallpaper &
fi

info "Starting OverviewApp"
qs -p "$QUICKSHELL_DIR/OverviewApp" &
