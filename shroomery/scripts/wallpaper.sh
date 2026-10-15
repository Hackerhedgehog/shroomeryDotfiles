#!/usr/bin/env bash
# Set the wallpaper and re-theme the desktop from it (matugen). Images go to awww;
# videos and GIFs to mpvpaper through animated-wallpaper.sh.
# Used by the WallpaperApp, autostart.sh and apply-theme.sh.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

IMAGE_PATH=""
NOTIFICATIONS=false
SKIP_WALLPAPER=false
SKIP_THEMING=false
THEME_FAILED=false
MONITOR_OUTPUT=""
AWWW_CROP_GRAVITY="center"
TRANSITION_EFFECT=$(setting wallpaper-transition-effect simple)
BLUR=$(setting wallpaper-blur 50x30)

show_help() {
    cat <<HELP
Usage: $(basename "$0") [PATH_TO_IMAGE_OR_VIDEO] [OPTIONS]
  With no image, the default wallpaper is used: $(default_wallpaper)

Options:
  --random [FOLDER]   Pick a random image or video from FOLDER (default: the wallpaper folder).
  --notifications     Send a desktop notification when done.
  --skip-wallpaper    Do not show it (theming only). Alias: --skip
  --skip-theming      Do not regenerate colors from the image.
  --monitor NAME      Only set the wallpaper on this output.
  --crop-gravity G    Anchor used when cropping (see 'awww img --crop-gravity').
  --help              Show this help.
HELP
}

send_notification() {
    [ "$NOTIFICATIONS" = true ] || return 0
    notify-send -a "Wallpaper" -i "preferences-desktop-wallpaper-symbolic" "$1" "$2"
}

# Wallpaper effects are scripts in shroomery/effects/ that edit $IMAGE_PATH in place; they run on
# a cached copy so the original stays untouched.
apply_effect() {
    local effect
    effect=$(setting wallpaper-effect off)
    [ "$effect" = "off" ] && return
    local script="$WALLPAPER_EFFECTS_DIR/$effect"
    if [ ! -f "$script" ]; then
        warn "Unknown wallpaper effect: $effect"
        return
    fi
    info "Applying wallpaper effect: $effect"
    local cached="$SHROOMERY_CACHE/$effect-$(basename "$IMAGE_PATH")"
    [ ! -f "$cached" ] && cp "$IMAGE_PATH" "$cached"
    IMAGE_PATH="$cached"
    source "$script"
}

set_wallpaper() {
    if [ "$SKIP_WALLPAPER" = true ]; then
        info "Wallpaper set skipped"
        return
    fi
    if [ "$ANIMATED" = true ]; then
        "$SHROOMERY_SCRIPTS/animated-wallpaper.sh" start "$IMAGE_PATH" "${MONITOR_OUTPUT:-ALL}"
        return
    fi
    set_still_wallpaper || return 1
    # The still is drawn: now take down any animated wallpaper above it.
    "$SHROOMERY_SCRIPTS/animated-wallpaper.sh" stop "${MONITOR_OUTPUT:-ALL}"
}

set_still_wallpaper() {
    local crop_args="" minor patch
    read -r minor patch <<< "$(awww --version | awk -F. '{print $2 " " $3}')"
    if (( minor > 12 || (minor == 12 && patch > 0) )); then
        crop_args="--resize crop --crop-gravity $AWWW_CROP_GRAVITY"
    fi
    info "Setting wallpaper: $IMAGE_PATH${MONITOR_OUTPUT:+ on monitor $MONITOR_OUTPUT}"
    local max=30 count=0
    # shellcheck disable=SC2086
    until awww img "$IMAGE_PATH" ${MONITOR_OUTPUT:+-o $MONITOR_OUTPUT} $crop_args --transition-type "$TRANSITION_EFFECT" 2>/dev/null; do
        (( count++ ))
        if (( count >= max )); then
            error "Failed to set wallpaper after ${max}s (no valid outputs)"
            return 1
        fi
        sleep 1
    done
}

# The accent settings (lib.sh) decide which of the image's colors seeds the
# palette, or whether a fixed accent color overrides it.
run_matugen() {
    info "Running matugen in $(current_mode) mode ($(accent_scheme), accent: $(accent_source))"
    palette_from_wallpaper "$STILL_PATH"
}

# Variants used by hyprlock, wlogout and the quickshell LauncherApp. Decoded once at screen size (jpeg:size lets the
# JPEG decoder downscale cheaply): processing a full-size original took ~20s on large images.
# Written to temp files and renamed, so a quick second apply never leaves a half-written image.
generate_image_variants() {
    local blur_args=() square_tmp="${SQUARE_WALLPAPER%.png}.$$.png" blurred_tmp="${BLURRED_WALLPAPER%.png}.$$.png"
    [ "$BLUR" != "0x0" ] && blur_args=(-blur "$BLUR")
    if magick -define jpeg:size=5120x5120 "$STILL_PATH" -resize '2560x2560>' \
        -define png:compression-level=1 \
        \( +clone -gravity Center -extent 1:1 -write "$square_tmp" +delete \) \
        "${blur_args[@]}" "$blurred_tmp"; then
        mv -f "$square_tmp" "$SQUARE_WALLPAPER"
        mv -f "$blurred_tmp" "$BLURRED_WALLPAPER"
    else
        rm -f "$square_tmp" "$blurred_tmp"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip|--skip-wallpaper) SKIP_WALLPAPER=true; shift ;;
        --skip-theming) SKIP_THEMING=true; shift ;;
        --random)
            if [[ -n "${2:-}" && "$2" != -* ]]; then
                folder=$(expand_path "$2"); shift 2
            else
                folder=$(wallpaper_folder); shift
            fi
            if [[ ! -d "$folder" ]]; then
                error "Directory does not exist -> $folder"; exit 1
            fi
            IMAGE_PATH=$(find "$folder" -maxdepth 1 -type f \
                \( "${IMAGE_FIND_ARGS[@]}" -o "${ANIMATED_FIND_ARGS[@]}" \) | shuf -n 1)
            [[ -z "$IMAGE_PATH" ]] && { error "No wallpapers found in -> $folder"; exit 1; }
            info "Random wallpaper selected: $IMAGE_PATH" ;;
        --notifications) NOTIFICATIONS=true; shift ;;
        --monitor) MONITOR_OUTPUT="$2"; shift 2 ;;
        --crop-gravity) AWWW_CROP_GRAVITY="$2"; shift 2 ;;
        --help|-h) show_help; exit 0 ;;
        -*) error "Unknown option: $1"; show_help; exit 1 ;;
        *)
            if [[ -n "$IMAGE_PATH" ]]; then
                error "Multiple image paths provided -> $1"; exit 1
            fi
            IMAGE_PATH="$1"; shift ;;
    esac
done

if [[ -z "$IMAGE_PATH" ]]; then
    IMAGE_PATH=$(default_wallpaper)
    info "Using default wallpaper -> $IMAGE_PATH"
fi
if [[ ! -f "$IMAGE_PATH" ]]; then
    error "Image file does not exist -> $IMAGE_PATH"; exit 1
fi

mkdir -p "$SHROOMERY_CACHE"
echo "$IMAGE_PATH" > "$WALLPAPER_CACHE_FILE"

# Videos and GIFs play through animated-wallpaper.sh (mpvpaper). Effects don't apply
# to them; theming and the hyprlock/launcher variants use their first frame.
ANIMATED=false
if is_animated "$IMAGE_PATH"; then
    ANIMATED=true
    STILL_PATH=$(video_frame "$IMAGE_PATH") || { error "Could not read a frame from $IMAGE_PATH"; exit 1; }
else
    apply_effect
    STILL_PATH="$IMAGE_PATH"
fi
echo "$STILL_PATH" > "$STILL_WALLPAPER_FILE"
# The screen-colors daemon decodes a video itself (animated-wallpaper.sh points
# this at the still while paused).
echo "$IMAGE_PATH" > "$DISPLAYED_WALLPAPER_FILE"
wait_for_awww || exit 1
set_wallpaper
if [ "$SKIP_THEMING" = true ]; then
    info "Theming skipped"
else
    # A failed palette is reported in the exit status (apply-theme.sh records
    # a choice only on success), but the rest of the wallpaper still applies.
    run_matugen || { error "matugen failed"; THEME_FAILED=true; }
    reload_theme_consumers
    # Only hyprlock, wlogout and the launcher use the variants (~1.5s): don't make the caller wait.
    # Detached from our stdout/stderr so a caller reading them sees EOF when we exit.
    generate_image_variants </dev/null >/dev/null 2>&1 &
    disown
    info "Updating wallpaper variants in the background"
fi
send_notification "Wallpaper Updated" "$(basename "$IMAGE_PATH")${MONITOR_OUTPUT:+ on output $MONITOR_OUTPUT}"
info "Done"
[ "$THEME_FAILED" = true ] && exit 1
exit 0
