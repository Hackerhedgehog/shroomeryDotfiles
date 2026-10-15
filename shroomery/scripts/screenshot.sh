#!/usr/bin/env bash
# Terminal screenshot tool. Saves to ~/Pictures/Screenshots and copies the
# image to the clipboard.
# Usage: screenshot.sh [area|window|fullscreen [DELAY_SECONDS]]
#        (no arguments: pick mode and delay with fzf)

save_dir="$HOME/Pictures/Screenshots"
path="$save_dir/screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"

take_screenshot() {
    local mode=$1 delay=${2:-0} geom
    mkdir -p "$save_dir"
    if [ "$delay" -gt 0 ]; then
        echo "⏱️ Waiting $delay seconds..."
        sleep "$delay"
    fi

    case $mode in
        fullscreen)
            grim "$path" ;;
        area)
            geom=$(slurp) || exit 0
            grim -g "$geom" "$path" ;;
        window)
            geom=$(hyprctl activewindow -j | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
            grim -g "$geom" "$path" ;;
        *)
            echo "Unknown mode: $mode (area|window|fullscreen)" >&2
            exit 1 ;;
    esac

    if [ -f "$path" ]; then
        wl-copy -t image/png < "$path"
        echo "✅ Saved $path (copied to clipboard)"
    else
        echo "❌ Screenshot failed" >&2
        exit 3
    fi
}

if [ "$#" -ge 1 ]; then
    take_screenshot "$1" "${2:-0}"
    exit 0
fi

mode=$(printf 'area\nwindow\nfullscreen\n' | fzf \
    --style full --height 15% --layout reverse --border \
    --prompt "🎯 Screenshot mode: " --header "ESC to cancel")
[ -z "$mode" ] && exit 0

delay=$(printf '0s\n2s\n5s\n10s\n' | fzf \
    --style full --height 15% --layout reverse --border \
    --prompt "⏳ Delay: " --header "Time before capture")
[ -z "$delay" ] && exit 0

take_screenshot "$mode" "${delay%s}"
