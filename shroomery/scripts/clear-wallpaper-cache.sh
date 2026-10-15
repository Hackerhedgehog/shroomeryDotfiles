#!/usr/bin/env bash
# Delete the generated wallpaper variants/effect copies and restore the default wallpaper.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

rm -rf "$SHROOMERY_CACHE"
mkdir -p "$SHROOMERY_CACHE"
info "Wallpaper cache cleared, restoring the default wallpaper"
"$SHROOMERY_SCRIPTS/wallpaper.sh"
