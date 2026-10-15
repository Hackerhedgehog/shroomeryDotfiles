#!/usr/bin/env bash
# Regenerate the color palette with matugen and reload everything that
# consumes it. Used by the SettingsApp accent picker, toggle-theme.sh and the
# gtk-theme listener.
#
#   apply-theme.sh --color '#rrggbb'  regenerate from a fixed source color
#   apply-theme.sh --wallpaper [N]    go back to the wallpaper-derived palette,
#                                     seeded by its Nth color (0 = most
#                                     dominant; default: the recorded one)
#   apply-theme.sh --scheme TYPE      switch the matugen scheme type (e.g.
#                                     scheme-vibrant) and re-apply
#   apply-theme.sh --reapply          re-apply the recorded source in the
#                                     current dark/light mode
#
# The choices are recorded in settings/accent, accent-index and accent-scheme
# (see the accent helpers in lib.sh), so a later dark/light flip, wallpaper
# change or reboot keeps them.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"
set -euo pipefail

usage() {
    echo "Usage: $0 --color '#rrggbb' | --wallpaper [0-$(( WALLPAPER_COLOR_COUNT - 1 ))] | --scheme TYPE | --reapply" >&2
    echo "Scheme types: ${ACCENT_SCHEMES[*]}" >&2
    exit 1
}

# Record only after the generator succeeded, so the recorded choice never
# diverges from the live palette.
record() {
    mkdir -p "$SHROOMERY_SETTINGS"
    printf '%s\n' "$2" > "$SHROOMERY_SETTINGS/$1"
}

apply_color() {
    local hex="$1"
    if ! is_hex_color "$hex"; then
        echo "Not a #rrggbb color: $hex" >&2
        exit 1
    fi
    palette_from_color "$hex"
    record accent "$hex"
    reload_theme_consumers
}

apply_wallpaper() {
    local wallpaper=""
    [ -f "$WALLPAPER_CACHE_FILE" ] && wallpaper=$(head -n 1 "$WALLPAPER_CACHE_FILE")
    [ -n "$wallpaper" ] || wallpaper=$(default_wallpaper)
    if [ ! -f "$wallpaper" ]; then
        echo "No wallpaper to derive a palette from: $wallpaper" >&2
        exit 1
    fi
    # Going through wallpaper.sh (rather than matugen directly) applies the
    # configured wallpaper effect first, so the palette matches what is on
    # screen. --skip-wallpaper avoids re-pushing the same image to awww.
    export ACCENT_SOURCE_OVERRIDE=wallpaper
    "$SHROOMERY_SCRIPTS/wallpaper.sh" --skip-wallpaper "$wallpaper"
    record accent wallpaper
}

# Re-apply whatever source is recorded (the overrides set by the caller win).
reapply() {
    local source
    source=$(accent_source)
    if [ "$source" = wallpaper ]; then
        apply_wallpaper
    else
        apply_color "$source"
    fi
}

case "${1:-}" in
    --color)
        [ $# -eq 2 ] || usage
        apply_color "$2"
        ;;
    --wallpaper)
        [ $# -le 2 ] || usage
        if [ $# -eq 2 ]; then
            [[ "$2" =~ ^[0-9]+$ ]] && (( $2 < WALLPAPER_COLOR_COUNT )) || usage
            export ACCENT_INDEX_OVERRIDE="$2"
        fi
        apply_wallpaper
        if [ $# -eq 2 ]; then
            record accent-index "$2"
        fi
        ;;
    --scheme)
        [ $# -eq 2 ] || usage
        is_accent_scheme "$2" || usage
        export ACCENT_SCHEME_OVERRIDE="$2"
        reapply
        record accent-scheme "$2"
        ;;
    --reapply)
        reapply
        ;;
    *)
        usage
        ;;
esac
