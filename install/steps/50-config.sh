#!/usr/bin/env bash
# Write first-run config (GTK, Qt, kitty, cursor), a default wallpaper and per-machine settings.
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

SHROOMERY="$REPO_DIR/shroomery"
SETTINGS="$SHROOMERY/settings"
HYPR="$REPO_DIR/hypr"

have jq || die "jq not found: run the packages step first (./install.sh --only packages)"
[ -L "$CONFIG_DIR/shroomery" ] || [ "$DRY_RUN" = 1 ] \
    || die "~/.config/shroomery isn't linked yet: run the link step first (./install.sh --only link)"

# --- folders -----------------------------------------------------------------
have xdg-user-dirs-update && run xdg-user-dirs-update
pictures=$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")
[ "$pictures" = "$HOME" ] && pictures="$HOME/Pictures"
# hypr/scripts/screenshot.sh saves to ~/Pictures/Screenshots
run mkdir -p "$HOME/.cache/shroomery" "$HOME/Pictures/Screenshots" "$pictures"
ok "folders ready"

# --- GTK, cursor, Qt, kitty (only written when missing) ----------------------
# The colors come from matugen (colors.css, written on the first wallpaper set).
for v in 3.0 4.0; do
    write_file "$CONFIG_DIR/gtk-$v/settings.ini" <<EOF
[Settings]
gtk-theme-name=Adwaita
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Fira Sans Semi-Bold 11
gtk-cursor-theme-name=Bibata-Modern-Ice
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=$([ "$v" = 3.0 ] && echo 1 || echo true)
EOF
    write_file "$CONFIG_DIR/gtk-$v/gtk.css" <<<"@import 'colors.css';"
done

# Apps that don't read the GTK setting (X11 ones) take the default cursor theme.
write_file "$HOME/.icons/default/index.theme" <<'EOF'
[Icon Theme]
Inherits=Bibata-Modern-Ice
EOF

# Qt apps go through qt6ct (hypr/environments.lua); matugen's post hook keeps
# color_scheme_path pointed at its palette.
for v in 5 6; do
    write_file "$CONFIG_DIR/qt${v}ct/qt${v}ct.conf" <<EOF
[Appearance]
color_scheme_path=$CONFIG_DIR/qt${v}ct/colors/matugen.conf
custom_palette=true
icon_theme=Papirus-Dark
standard_dialogs=default
style=Fusion
EOF
done

write_file "$CONFIG_DIR/kitty/kitty.conf" <<'EOF'
font_family                 JetBrainsMono Nerd Font
font_size                   12
remember_window_size        no
initial_window_width        950
initial_window_height       500
scrollback_lines            2000
enable_audio_bell           no
window_padding_width        10
hide_window_decorations     yes
background_opacity          0.7
dynamic_background_opacity  yes
confirm_os_window_close     0
cursor_trail                1
# Colors written by matugen with every wallpaper change
include colors-matugen.conf
EOF

# --- a wallpaper to start from -----------------------------------------------
# The repo ships two wallpapers (settings/wallpaper-default picks the first one
# set). When the folder is still empty (a custom wallpaper-folder, or they were
# deleted), the theme pipeline has no image to take colors from, so paint one: blurred clouds in two tones, a
# dark base and a warm accent for matugen to build the palette around.
# (shroomery/lib.sh in a subshell: it has its own info/warn helpers)
shroomery_lib() { bash -c 'source "$1" && "$2"' _ "$SHROOMERY/lib.sh" "$1" 2>/dev/null; }
folder=$(shroomery_lib wallpaper_folder)
folder=${folder:-$REPO_DIR/quickshell/WallpaperApp/wallpapers}
if [ -n "$(shroomery_lib default_wallpaper)" ]; then
    ok "wallpapers found in ${folder/#$HOME/\~}"
elif ! have magick; then
    warn "ImageMagick isn't installed yet: no default wallpaper (run the packages step, then this one again)"
else
    info "no wallpapers yet: painting ${folder/#$HOME/\~}/default.jpg"
    run mkdir -p "$folder/animated"
    run magick -size 960x540 plasma:fractal -blur 0x30 -colorspace gray -auto-level \
        -sigmoidal-contrast 4,60% +level-colors '#110e1a','#b8644a' \
        -resize 3840x2160! -quality 92 "$folder/default.jpg" \
        && ok "default wallpaper painted (add your own to that folder, Super+P picks one)"
fi

# --- machine-specific settings ------------------------------------------------
# The repo carries its author's monitor layout, keyboard layout and so on.
# Reset them on a fresh install so the first login works on this machine.
default=n
[ "$SHROOMERY_FRESH" = 1 ] && default=y
echo
info "The repo comes with another machine's monitor layout and keyboard layout."
if ! ask_yn "Reset monitors, keyboard layout and visualizer screen for this PC?" "$default"; then
    ok "kept the per-machine settings"
    exit 0
fi

# Monitors: one rule for every screen (preferred mode, auto position).
# Arrange them later in the MonitorApp (Super+M), which rewrites this block.
FORCE=1 write_file "$HYPR/monitors.lua" <<'EOF'
-- BEGIN control_controls
hl.monitor({
  output = "",
  mode = "highres highrr",
  position = "auto",
  scale = 1,
})
-- END control_controls
EOF

# Keyboard layout: the X11 layout localectl knows, else "us".
guess=$(localectl status 2>/dev/null | awk -F': ' '/X11 Layout/ { print $2; exit }' | cut -d, -f1)
guess=${guess:-us}
valid_layouts=$("$SHROOMERY/scripts/input.sh" layouts 2>/dev/null | cut -f1)
while true; do
    layout=$(ask "Keyboard layout (xkb code: us, de, fr, gb, ee, … — change later with Super+I)" "$guess")
    if [ -z "$valid_layouts" ] || grep -qxF "$layout" <<<"$valid_layouts"; then
        break
    fi
    warn "'$layout' isn't an xkb layout. Some codes: $(grep -E '^(us|gb|de|fr|es|it|se|no|fi|dk|ee|pl|ru|ua|cz|pt|br|nl|tr)$' <<<"$valid_layouts" | tr '\n' ' ')"
    [ "$ASSUME_YES" = 1 ] && { layout=us; break; }
done

if [ "$DRY_RUN" = 1 ]; then
    info "[dry-run] would set keyboard layout $layout in settings/input.json and hypr/input.lua"
else
    tmp=$(mktemp)
    jq --arg l "$layout" '.layout = $l | .variant = ""' "$SETTINGS/input.json" > "$tmp" \
        && cat "$tmp" > "$SETTINGS/input.json"
    rm -f "$tmp"
    # Writes the shroomery_input block in hypr/input.lua; applying it live
    # fails outside Hyprland (exit 2), which is fine here.
    "$SHROOMERY/scripts/input.sh" apply >/dev/null 2>&1
    if [ $? -le 2 ] && grep -qF "kb_layout     = \"$layout\"" "$HYPR/input.lua"; then
        ok "keyboard layout: $layout"
    else
        warn "couldn't write the keyboard layout to hypr/input.lua (set it with Super+I later)"
    fi
fi

# The visualizer picks the first screen again.
if [ "$DRY_RUN" != 1 ] && [ -f "$SETTINGS/visualizer.json" ]; then
    tmp=$(mktemp)
    jq '.monitor = ""' "$SETTINGS/visualizer.json" > "$tmp" && cat "$tmp" > "$SETTINGS/visualizer.json"
    rm -f "$tmp"
fi
ok "visualizer screen reset"

# Hyprland's locale (date names) follows the system language.
lang=$(sed -n 's/^LANG=//p' /etc/locale.conf 2>/dev/null | cut -d. -f1)
lang=${lang:-en_US}
run sed -i -E "s/^(\s*locale\s*=\s*)\"[^\"]*\"/\1\"$lang\"/" "$HYPR/decorations.lua"
ok "Hyprland locale: $lang"
