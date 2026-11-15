#!/usr/bin/env bash
# Shared paths and helpers for every shroomery script. Source it:
#   source "$(dirname "$(readlink -f "$0")")/../lib.sh"
#
# The QML side keeps the same paths in quickshell/shared/Paths.qml — change
# both together.

SHROOMERY_DIR="$HOME/.config/shroomery"
SHROOMERY_SCRIPTS="$SHROOMERY_DIR/scripts"
SHROOMERY_SETTINGS="$SHROOMERY_DIR/settings"
SHROOMERY_COLORS="$SHROOMERY_DIR/colors"
WALLPAPER_EFFECTS_DIR="$SHROOMERY_DIR/effects"
SHROOMERY_CACHE="$HOME/.cache/shroomery"
# Runtime state, gone after a reboot: the screen-colors socket/lock, the
# visualizer-active flag and generated cava configs (quickshell Paths.runtimeDir).
SHROOMERY_RUNTIME="${XDG_RUNTIME_DIR:-/tmp}/shroomery"

QUICKSHELL_DIR="$HOME/.config/quickshell"
DEFAULT_WALLPAPER_FOLDER="$QUICKSHELL_DIR/WallpaperApp/wallpapers"
GTK3_SETTINGS_FILE="$HOME/.config/gtk-3.0/settings.ini"
GTK4_SETTINGS_FILE="$HOME/.config/gtk-4.0/settings.ini"

# Wallpaper state written by scripts/wallpaper.sh and read by hyprlock,
# wlogout, the WallpaperApp and the LauncherApp.
WALLPAPER_CACHE_FILE="$SHROOMERY_CACHE/current_wallpaper"
# The image awww actually shows: the effect copy, or the original with no effect
# (read by the screen-colors daemon as its wallpaper base).
DISPLAYED_WALLPAPER_FILE="$SHROOMERY_CACHE/displayed_wallpaper"
BLURRED_WALLPAPER="$SHROOMERY_CACHE/blurred_wallpaper.png"
SQUARE_WALLPAPER="$SHROOMERY_CACHE/square_wallpaper.png"
# A still of the wallpaper: the image itself, or an animated wallpaper's first
# frame (FRAMES_DIR). Read by the WallpaperApp preview and the visualizer's mini screen.
STILL_WALLPAPER_FILE="$SHROOMERY_CACHE/still_wallpaper"
FRAMES_DIR="$SHROOMERY_CACHE/frames"
# Grid previews written by scripts/wallpaper-thumbnails.sh.
WALLPAPER_THUMBNAILS="$SHROOMERY_CACHE/thumbnails"
# Animated wallpapers (scripts/animated-wallpaper.sh): what should play, one
# "OUTPUT<TAB>FILE<TAB>SECONDS" line per mpvpaper (OUTPUT ALL = every monitor;
# SECONDS = where to resume after a pause). Kept across reboots.
ANIMATED_STATE_FILE="$SHROOMERY_CACHE/animated-wallpaper"
# Per running mpvpaper: OUTPUT.pid, OUTPUT.sock (mpv IPC), plus paused-OUTPUT.png
# while paused (the frame awww shows meanwhile).
ANIMATED_RUNTIME="$SHROOMERY_RUNTIME/mpvpaper"
# The wallpaper's candidate source colors (one #rrggbb per line, most dominant
# first), written by palette_from_wallpaper for the SettingsApp accent picker.
WALLPAPER_COLORS_FILE="$SHROOMERY_CACHE/wallpaper-colors"

# matugen scheme types the accent picker offers; the first is the default.
ACCENT_SCHEMES=(scheme-tonal-spot scheme-vibrant scheme-expressive scheme-content
    scheme-fidelity scheme-fruit-salad scheme-rainbow scheme-neutral scheme-monochrome)
# How many of the wallpaper's colors the picker offers.
WALLPAPER_COLOR_COUNT=3

# Safe system update (scripts/pkg-update.sh). Root-owned storage, world-readable:
# known-good/ pending/ logs/ recovery.sh. Archives in it are hardlinks into the
# pacman cache, so both must be on one filesystem.
RECOVERY_DIR="/var/lib/shroomery/recovery"
PKG_CACHE_DIR="${PKG_CACHE_DIR:-/var/cache/pacman/pkg}"   # tests override it
# Patterns of the protected package set (one per line; missing = built-in list).
PROTECTED_FILE="$SHROOMERY_SETTINGS/recovery-protected"
# How many versions per package `paccache` keeps (default 3).
CACHE_KEEP_FILE="$SHROOMERY_SETTINGS/cache-keep"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Print a settings value (first line, trimmed), or $2 when the file is missing
# or empty.
setting() {
    local file="$SHROOMERY_SETTINGS/$1" value=""
    [ -f "$file" ] && value=$(head -n 1 "$file" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    printf '%s\n' "${value:-$2}"
}

# Expand a leading ~ or $HOME in a path read from a settings file.
expand_path() {
    local p="${1//\$HOME/$HOME}"
    printf '%s\n' "${p//\~/$HOME}"
}

wallpaper_folder() {
    expand_path "$(setting wallpaper-folder "$DEFAULT_WALLPAPER_FOLDER")"
}

# Animated wallpapers live in the wallpaper folder's animated/ subfolder.
animated_folder() {
    printf '%s/animated\n' "$(wallpaper_folder)"
}

# find(1) name tests for still images and for animated wallpapers (played by mpvpaper).
IMAGE_FIND_ARGS=(-iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png")
ANIMATED_FIND_ARGS=(-iname "*.mp4" -o -iname "*.webm" -o -iname "*.mkv" -o -iname "*.mov"
    -o -iname "*.m4v" -o -iname "*.avi" -o -iname "*.gif")

# True for a video or GIF (by extension).
is_animated() {
    case "${1,,}" in
        *.mp4 | *.webm | *.mkv | *.mov | *.m4v | *.avi | *.gif) return 0 ;;
        *) return 1 ;;
    esac
}

# Print the path of an animated wallpaper's first frame as a PNG, extracting it
# (once per file version) into FRAMES_DIR.
video_frame() {
    local video="$1" frame tmp
    frame="$FRAMES_DIR/$(printf '%s' "$video" | md5sum | cut -d' ' -f1).png"
    if [ ! -s "$frame" ] || [ "$video" -nt "$frame" ]; then
        mkdir -p "$FRAMES_DIR"
        tmp="$frame.$$.png"
        if ! ffmpeg -v error -y -i "$video" -frames:v 1 "$tmp" </dev/null; then
            rm -f "$tmp"
            return 1
        fi
        mv -f "$tmp" "$frame"
    fi
    printf '%s\n' "$frame"
}

# On battery: a mains adapter exists and is offline. Desktops (no adapter) never are.
on_battery() {
    local supply
    for supply in /sys/class/power_supply/*; do
        [ "$(cat "$supply/type" 2>/dev/null)" = Mains ] || continue
        [ "$(cat "$supply/online" 2>/dev/null)" = 0 ] && return 0
    done
    return 1
}

gamemode_on() {
    [ -f "$SHROOMERY_SETTINGS/gamemode-enabled" ]
}

# Wait (up to 30 s) until awww-daemon answers.
wait_for_awww() {
    local max=300 count=0
    until awww query >/dev/null 2>&1; do
        (( count++ ))
        if (( count >= max )); then
            error "awww-daemon did not start within 30s"
            return 1
        fi
        sleep 0.1
    done
}

# The fallback wallpaper: the file settings/wallpaper-default names in the
# wallpaper folder, else default.* there, else its first image.
default_wallpaper() {
    local folder name
    folder=$(wallpaper_folder)
    name=$(setting wallpaper-default "")
    if [ -n "$name" ] && [ -f "$folder/$name" ]; then
        printf '%s\n' "$folder/$name"
        return
    fi
    find "$folder" -maxdepth 1 -type f \( "${IMAGE_FIND_ARGS[@]}" \) 2>/dev/null \
        | sort | awk -F/ '{ if ($NF ~ /^default\./) { print; found=1; exit } else if (!first) first=$0 } END { if (!found && first) print first }'
}

matugen_bin() {
    local bin="matugen"
    [ -f "$HOME/.cargo/bin/matugen" ] && bin="$HOME/.cargo/bin/matugen"
    [ -f "$HOME/.local/bin/matugen" ] && bin="$HOME/.local/bin/matugen"
    echo "$bin"
}

# dark when GTK prefers a dark theme, light otherwise. The GTK boolean can be
# written as 1/0 or true/false.
current_mode() {
    local pref=""
    if [ -f "$GTK3_SETTINGS_FILE" ]; then
        pref=$(grep -E '^gtk-application-prefer-dark-theme=' "$GTK3_SETTINGS_FILE" \
            | awk -F'=' '{print $2}' || true)
    fi
    case "$pref" in
        1 | true) echo dark ;;
        *)        echo light ;;
    esac
}

# --- Accent: what the palette is generated from ---
# settings/accent is "wallpaper" or a #rrggbb color, settings/accent-index picks
# one of the wallpaper's colors (0 = most dominant) and settings/accent-scheme
# the matugen scheme type. apply-theme.sh sets ACCENT_*_OVERRIDE to try a new
# choice before recording it, so a rejected choice never reaches the settings.

is_hex_color() {
    [[ "$1" =~ ^#[0-9A-Fa-f]{6}$ ]]
}

# "wallpaper" or a #rrggbb color; anything unreadable counts as wallpaper.
accent_source() {
    local source="${ACCENT_SOURCE_OVERRIDE:-$(setting accent wallpaper)}"
    if is_hex_color "$source"; then
        echo "$source"
    else
        echo wallpaper
    fi
}

accent_index() {
    local index="${ACCENT_INDEX_OVERRIDE:-$(setting accent-index 0)}"
    if [[ "$index" =~ ^[0-9]+$ ]] && (( index < WALLPAPER_COLOR_COUNT )); then
        echo "$index"
    else
        echo 0
    fi
}

is_accent_scheme() {
    local scheme
    for scheme in "${ACCENT_SCHEMES[@]}"; do
        [ "$scheme" = "$1" ] && return 0
    done
    return 1
}

accent_scheme() {
    local scheme="${ACCENT_SCHEME_OVERRIDE:-$(setting accent-scheme "${ACCENT_SCHEMES[0]}")}"
    if is_accent_scheme "$scheme"; then
        echo "$scheme"
    else
        echo "${ACCENT_SCHEMES[0]}"
    fi
}

# Record the wallpaper's candidate colors for the accent picker. Written to a
# temp file and renamed so the picker never reads a half-written list.
cache_wallpaper_colors() {
    local tmp="$WALLPAPER_COLORS_FILE.$$"
    mkdir -p "$SHROOMERY_CACHE"
    "$(matugen_bin)" image "$1" --show-source-colors 2>/dev/null \
        | sed 's/\x1b\[[0-9;]*m//g' | grep -oE '#[0-9A-Fa-f]{6}' \
        | head -n "$WALLPAPER_COLOR_COUNT" > "$tmp" || true
    mv -f "$tmp" "$WALLPAPER_COLORS_FILE"
}

# Generate the palette for a wallpaper image: from the chosen one of its
# colors, or from the fixed accent color when one is set (a fixed accent
# survives wallpaper changes).
palette_from_wallpaper() {
    local image="$1" source index count
    cache_wallpaper_colors "$image"
    source=$(accent_source)
    if [ "$source" != wallpaper ]; then
        palette_from_color "$source"
        return
    fi
    index=$(accent_index)
    # An image can yield fewer colors than the index asks for.
    count=$(wc -l < "$WALLPAPER_COLORS_FILE")
    (( count > 0 && index >= count )) && index=$(( count - 1 ))
    "$(matugen_bin)" image "$image" --source-color-index "$index" \
        -t "$(accent_scheme)" -m "$(current_mode)"
}

palette_from_color() {
    "$(matugen_bin)" color hex "$1" -t "$(accent_scheme)" -m "$(current_mode)"
}

# Read one color (e.g. primary) from the matugen-generated palette.
palette_color() {
    grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"#[0-9A-Fa-f]{6}\"" "$SHROOMERY_COLORS/colors.json" 2>/dev/null \
        | grep -oE '#[0-9A-Fa-f]{6}'
}

# The configured terminal emulator command.
terminal_cmd() {
    setting terminal kitty
}

# Reload everything that reads the matugen palette.
reload_theme_consumers() {
    if pgrep -x qs >/dev/null; then
        qs ipc call theme-manager reload >/dev/null 2>&1 || true
        info "Quickshell theme reloaded"
    fi

    # Only when swaync runs: with Quickshell owning the notification bus,
    # swaync-client waits forever for a daemon that never answers.
    if pgrep -x swaync >/dev/null && command -v swaync-client >/dev/null 2>&1; then
        timeout 3 swaync-client -rs >/dev/null 2>&1 || true
    fi

    if command -v pywalfox >/dev/null 2>&1; then
        pywalfox update >/dev/null 2>&1 || true
    fi
}

# --- night light (scripts/hyprsunset.sh, listeners/night-light.sh) ---
# Settings JSON written by the quickshell SettingsApp panel (Paths.nightLightSettings).
NIGHT_LIGHT_SETTINGS="$SHROOMERY_SETTINGS/night-light.json"
# "YYYY-MM-DD SUNRISE SUNSET" from wttr.in, refreshed once a day.
SUN_TIMES_FILE="$SHROOMERY_CACHE/sun-times"

# Minutes since midnight of an H:MM / HH:MM (24 h) time; exit 1 when malformed.
time_to_minutes() {
    [[ "$1" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]] || return 1
    echo $(( 10#${BASH_REMATCH[1]} * 60 + 10#${BASH_REMATCH[2]} ))
}

# Exit 0 when NOW is inside [START, END) (all in minutes). START > END
# crosses midnight; START == END is an empty window.
time_in_window() {
    local now=$1 start=$2 end=$3
    if (( start < end )); then
        (( now >= start && now < end ))
    elif (( start > end )); then
        (( now >= start || now < end ))
    else
        return 1
    fi
}

# VALUE rounded and clamped to MIN..MAX; DEFAULT when it isn't a number.
clamp_int() {
    local v
    if ! [[ "$1" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        echo "$4"
        return
    fi
    v=$(LC_NUMERIC=C printf '%.0f' "$1")
    (( v < $2 )) && v=$2
    (( v > $3 )) && v=$3
    echo "$v"
}

# A validated night-light.json value (mode, on, off, temperature, gamma);
# missing file, bad JSON or bad values give the default. Same rules as
# quickshell SettingsApp/NightLightLogic.js normalize().
night_light_setting() {
    local raw m
    raw=$(jq -r --arg k "$1" '.[$k] // empty | tostring' "$NIGHT_LIGHT_SETTINGS" 2>/dev/null)
    case $1 in
        mode)
            if [[ "$raw" =~ ^(off|fixed|sun)$ ]]; then echo "$raw"; else echo off; fi ;;
        on|off)
            if m=$(time_to_minutes "$raw"); then
                printf '%02d:%02d\n' $((m / 60)) $((m % 60))
            elif [ "$1" = on ]; then
                echo 21:00
            else
                echo 07:00
            fi ;;
        temperature) clamp_int "$raw" 2500 6500 4500 ;;
        gamma) clamp_int "$raw" 50 100 100 ;;
    esac
}

# What listeners/night-light.sh does this pass: prints on/off, or nothing.
# It acts only when WANTED changed since LAST, so a manual toggle holds until
# the next on/off time — unless GAP (seconds since the last pass) shows a
# suspend, after which a change may have been missed and the schedule wins.
night_light_action() {
    local last=$1 wanted=$2 gap=$3
    [ "$wanted" = none ] && return
    if [ "$wanted" != "$last" ] || (( gap > 180 )); then
        echo "$wanted"
    fi
}

# --- input (scripts/input.sh, listeners/input-speed.sh) ---
# Settings JSON written by the quickshell InputApp (Paths.inputSettings).
INPUT_SETTINGS="$SHROOMERY_SETTINGS/input.json"
# The Hyprland file input.sh writes its managed block into (Paths.hyprInput).
HYPR_INPUT_FILE="$HOME/.config/hypr/input.lua"
# The mouse speed in input.json is the speed on a screen this many logical
# pixels high (a 1080p monitor at scale 1).
INPUT_REFERENCE_HEIGHT=1080
# The speed actually set is kept in this range.
INPUT_SPEED_MIN=0.05
INPUT_SPEED_MAX=10

# VALUE (a decimal number) clamped to MIN..MAX with 3 decimals; DEFAULT when
# it isn't a number.
clamp_decimal() {
    if ! [[ "$1" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        echo "$4"
        return
    fi
    LC_ALL=C awk -v v="$1" -v lo="$2" -v hi="$3" \
        'BEGIN { if (v < lo) v = lo; if (v > hi) v = hi; printf "%.3f\n", v }'
}

# A validated input.json value (layout, variant, speed, scaleWithMonitor);
# missing file, bad JSON or bad values give the default. Same rules as
# quickshell InputApp/InputLogic.js normalize().
input_setting() {
    local raw
    raw=$(jq -r --arg k "$1" '.[$k] // empty | tostring' "$INPUT_SETTINGS" 2>/dev/null)
    case $1 in
        layout)
            if [[ "$raw" =~ ^[A-Za-z0-9_-]+$ ]]; then echo "$raw"; else echo us; fi ;;
        variant)
            if [[ "$raw" =~ ^[A-Za-z0-9_-]+$ ]]; then echo "$raw"; else echo ""; fi ;;
        speed) clamp_decimal "$raw" 0.05 4 1.000 ;;
        scaleWithMonitor)
            if [ "$raw" = true ]; then echo true; else echo false; fi ;;
    esac
}

# How much faster the cursor has to move on a monitor so it crosses it as
# fast as a 1080p screen at scale 1: its logical height / 1080. Monitors
# rotated by 90° or 270° (TRANSFORM 1, 3, 5, 7) use their width.
# monitor_speed_factor WIDTH HEIGHT SCALE TRANSFORM → "1.333"; 1.000 on bad input.
monitor_speed_factor() {
    local w=$1 h=$2 scale=$3 transform=${4:-0}
    if ! [[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ && "$scale" =~ ^[0-9]+(\.[0-9]+)?$ ]] \
        || (( w == 0 || h == 0 )); then
        echo 1.000
        return
    fi
    (( transform % 2 == 1 )) && h=$w
    LC_ALL=C awk -v h="$h" -v s="$scale" -v ref="$INPUT_REFERENCE_HEIGHT" \
        'BEGIN { if (s <= 0) s = 1; printf "%.3f\n", h / s / ref }'
}

# The speed to set: BASE × FACTOR, clamped to INPUT_SPEED_MIN..MAX.
effective_speed() {
    local product
    product=$(LC_ALL=C awk -v b="$1" -v f="$2" 'BEGIN { printf "%.4f\n", b * f }')
    clamp_decimal "$product" "$INPUT_SPEED_MIN" "$INPUT_SPEED_MAX" 1.000
}

# Hyprland's accel_profile for a flat (no acceleration) speed: libinput's
# custom curve through (0, 0) and (1, SPEED) moves the cursor SPEED× the
# mouse's motion at any hand speed.
flat_accel_profile() {
    echo "custom 1 0 $1"
}

# --- date, time and locale (scripts/time.sh, listeners/auto-timezone.sh) ---
# Settings JSON written by the quickshell TimeApp (Paths.timeSettings).
TIME_SETTINGS="$SHROOMERY_SETTINGS/time.json"
# The polkit rule time.sh allow-timezone installs (readable by root only).
TIMEZONE_POLKIT_RULE="/etc/polkit-1/rules.d/49-shroomery-timezone.rules"
# Locale variables localectl set-locale accepts.
LOCALE_VARS=(LANG LANGUAGE LC_CTYPE LC_NUMERIC LC_TIME LC_COLLATE LC_MONETARY LC_MESSAGES
    LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT LC_IDENTIFICATION)

# Status bar settings (quickshell StatusbarState, Paths.statusbarSettings); its
# "clock" group is the clock format the TimeApp sets.
STATUSBAR_SETTINGS="$SHROOMERY_SETTINGS/statusbar.json"

# Exit 0 when the shell's clock is 24-hour: statusbar.json clock.format (a Qt
# pattern, default HH:mm) has no AP/ap outside 'quoted' text. Same rule as
# quickshell TimeApp/TimeLogic.js parseTimeFormat. Unreadable file → 24-hour.
clock_is_24h() {
    local fmt
    fmt=$(jq -r '.clock.format // "HH:mm"' "$STATUSBAR_SETTINGS" 2>/dev/null) || fmt="HH:mm"
    fmt=$(sed "s/'[^']*'//g" <<<"$fmt")
    [[ "${fmt,,}" != *a* ]]
}

# A validated time.json value (autoTimezone); missing file or bad values → default.
time_setting() {
    local raw
    raw=$(jq -r --arg k "$1" '.[$k] // empty | tostring' "$TIME_SETTINGS" 2>/dev/null)
    case $1 in
        autoTimezone)
            if [ "$raw" = true ]; then echo true; else echo false; fi ;;
    esac
}

# Exit 0 when TEXT is "YYYY-MM-DD HH:MM" or "YYYY-MM-DD HH:MM:SS" with a real
# date and time (for timedatectl set-time).
valid_datetime() {
    [[ "$1" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})\ ([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$ ]] || return 1
    date -d "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}" +%F 2>/dev/null \
        | grep -qx "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
}

# Exit 0 when ARG is VAR=VALUE with VAR one of LOCALE_VARS and VALUE a locale
# name (en_US.UTF-8, sr_RS@latin, C.UTF-8); an empty VALUE is not accepted.
valid_locale_assignment() {
    local var=${1%%=*} value=${1#*=} v
    [[ "$1" == *=* && "$value" =~ ^[A-Za-z0-9_.@:-]+$ ]] || return 1
    for v in "${LOCALE_VARS[@]}"; do
        [ "$v" = "$var" ] && return 0
    done
    return 1
}

# A locale name as `locale -a` prints it: en_US.UTF-8 → en_US.utf8.
normalize_locale_name() {
    local name=$1 base codeset mod=""
    if [[ "$name" == *@* ]]; then mod="@${name#*@}"; name=${name%%@*}; fi
    if [[ "$name" == *.* ]]; then
        base=${name%%.*}
        codeset=${name#*.}
        codeset=${codeset,,}
        codeset=${codeset//-/}
        echo "$base.$codeset$mod"
    else
        echo "$name$mod"
    fi
}
