#!/usr/bin/env bash
# Keyboard layout and mouse speed from settings/input.json (written by the
# quickshell InputApp, SUPER+I). The mouse never accelerates: the speed is a
# flat multiplier (lib.sh flat_accel_profile). With scaleWithMonitor the speed
# in the file is the speed on a 1080p screen at scale 1, and each monitor gets
# it times its logical height / 1080 (lib.sh monitor_speed_factor), so the
# cursor crosses every screen in the same hand distance.
#
# Usage: input.sh COMMAND
#   apply             write the managed block in ~/.config/hypr/input.lua and
#                     apply layout + speed now
#   speed [MONITOR]   apply the mouse speed for MONITOR (default: the focused
#                     one); listeners/input-speed.sh calls this on every
#                     monitor change. Does nothing while input.json is missing.
#   info              JSON: the focused monitor, its factor, the speed now,
#                     and Hyprland's live kb_layout / kb_variant
#   layouts           "CODE<TAB>DESCRIPTION" per xkb layout
#   variants LAYOUT   "CODE<TAB>DESCRIPTION" per variant of LAYOUT
# Exit 1 = bad arguments or values, 2 = hyprctl failed.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

XKB_RULES="/usr/share/X11/xkb/rules/evdev.lst"
BLOCK_BEGIN="-- BEGIN shroomery_input"
BLOCK_END="-- END shroomery_input"

# The monitor JSON object for NAME, or the focused one; {} when not found.
monitor_json() {
    local name=${1:-}
    hyprctl monitors -j 2>/dev/null | jq -c --arg n "$name" '
        (if $n == "" then map(select(.focused)) else map(select(.name == $n)) end)
        | .[0] // {}'
}

# Factor for a monitor JSON object (1.000 when scaling is off or it's unknown).
factor_of() {
    if [ "$(input_setting scaleWithMonitor)" != true ]; then
        echo 1.000
        return
    fi
    local w h s t
    read -r w h s t < <(jq -r '"\(.width // 0) \(.height // 0) \(.scale // 1) \(.transform // 0)"' <<<"$1")
    monitor_speed_factor "$w" "$h" "$s" "$t"
}

speed_for() {
    effective_speed "$(input_setting speed)" "$(factor_of "$(monitor_json "${1:-}")")"
}

layout_codes() {
    awk '/^! layout/ { on = 1; next } /^!/ { on = 0 } on && NF { print $1 }' "$XKB_RULES" 2>/dev/null
}

list_layouts() {
    awk '/^! layout/ { on = 1; next } /^!/ { on = 0 }
        on && NF { code = $1; sub(/^[ \t]*[^ \t]+[ \t]+/, ""); print code "\t" $0 }' "$XKB_RULES"
}

# Variant lines look like "  nodeadkeys      de: German (no dead keys)".
list_variants() {
    awk -v want="$1" '/^! variant/ { on = 1; next } /^!/ { on = 0 }
        on && NF && $2 == want ":" { code = $1; sub(/^[ \t]*[^ \t]+[ \t]+[^ \t]+[ \t]+/, ""); print code "\t" $0 }' "$XKB_RULES"
}

check_layout() {
    local layout=$1 variant=$2
    [ -f "$XKB_RULES" ] || return 0
    if ! layout_codes | grep -qxF "$layout"; then
        error "Unknown keyboard layout: $layout"
        return 1
    fi
    if [ -n "$variant" ] && ! list_variants "$layout" | cut -f1 | grep -qxF "$variant"; then
        error "Layout $layout has no variant $variant"
        return 1
    fi
}

# The Lua table body every write and live apply uses.
input_lua() {
    printf 'kb_layout = "%s", kb_variant = "%s", accel_profile = "%s"' \
        "$1" "$2" "$(flat_accel_profile "$3")"
}

# Replace (or append) the managed block in input.lua. Only writes when the
# text changes, and in place, so Hyprland's config watcher keeps its inode.
write_block() {
    local layout=$1 variant=$2 speed=$3 block tmp
    block=$(cat <<LUA
$BLOCK_BEGIN
-- Written by ~/.config/shroomery/scripts/input.sh from settings/input.json;
-- change it in the InputApp (SUPER+I). The speed is a flat multiplier (no
-- acceleration); listeners/input-speed.sh adjusts it per monitor.
hl.config({
    input = {
        kb_layout     = "$layout",
        kb_variant    = "$variant",
        accel_profile = "$(flat_accel_profile "$speed")",
    },
})
$BLOCK_END
LUA
)
    tmp=$(mktemp)
    if [ -f "$HYPR_INPUT_FILE" ] && grep -qxF -- "$BLOCK_BEGIN" "$HYPR_INPUT_FILE"; then
        awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" -v block="$block" '
            $0 == b { print block; skip = 1; next }
            $0 == e && skip { skip = 0; next }
            !skip { print }' "$HYPR_INPUT_FILE" > "$tmp"
    else
        { [ -f "$HYPR_INPUT_FILE" ] && cat "$HYPR_INPUT_FILE"; echo; echo "$block"; } > "$tmp"
    fi
    if ! cmp -s "$tmp" "$HYPR_INPUT_FILE"; then
        cat "$tmp" > "$HYPR_INPUT_FILE"
    fi
    rm -f "$tmp"
}

hypr_eval() {
    hyprctl eval "hl.config({ input = { $1 } })" >/dev/null 2>&1 || {
        error "hyprctl eval failed"
        return 2
    }
}

apply() {
    local layout variant speed
    layout=$(input_setting layout)
    variant=$(input_setting variant)
    check_layout "$layout" "$variant" || exit 1
    speed=$(speed_for)
    write_block "$layout" "$variant" "$speed"
    hypr_eval "$(input_lua "$layout" "$variant" "$speed")" || exit 2
}

speed() {
    [ -f "$INPUT_SETTINGS" ] || return 0
    hypr_eval "accel_profile = \"$(flat_accel_profile "$(speed_for "${1:-}")")\"" || exit 2
}

show_info() {
    local mon factor live_layout live_variant
    mon=$(monitor_json "")
    factor=$(factor_of "$mon")
    live_layout=$(hyprctl getoption input:kb_layout -j 2>/dev/null | jq -r '.str // ""')
    live_variant=$(hyprctl getoption input:kb_variant -j 2>/dev/null | jq -r '.str // ""')
    jq -n --argjson m "$mon" --arg f "$factor" --arg s "$(effective_speed "$(input_setting speed)" "$factor")" \
        --arg rf "$(monitor_speed_factor \
            "$(jq -r '.width // 0' <<<"$mon")" "$(jq -r '.height // 0' <<<"$mon")" \
            "$(jq -r '.scale // 1' <<<"$mon")" "$(jq -r '.transform // 0' <<<"$mon")")" \
        --arg ll "$live_layout" --arg lv "$live_variant" \
        --argjson exists "$([ -f "$INPUT_SETTINGS" ] && echo true || echo false)" '{
            monitor: ($m.name // ""), width: ($m.width // 0), height: ($m.height // 0),
            scale: ($m.scale // 1), transform: ($m.transform // 0),
            monitorFactor: ($rf | tonumber), factor: ($f | tonumber), speed: ($s | tonumber),
            liveLayout: $ll, liveVariant: $lv, settingsExist: $exists
        }'
}

case "${1:-}" in
    apply)    apply ;;
    speed)    speed "${2:-}" ;;
    info)     show_info ;;
    layouts)  list_layouts ;;
    variants) [ -n "${2:-}" ] || { error "variants needs a layout"; exit 1; }; list_variants "$2" ;;
    *)
        echo "Usage: $(basename "$0") apply | speed [MONITOR] | info | layouts | variants LAYOUT" >&2
        exit 1 ;;
esac
