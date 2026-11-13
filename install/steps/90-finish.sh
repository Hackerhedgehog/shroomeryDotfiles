#!/usr/bin/env bash
# Show what to do next and the most useful keybinds.
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cat <<EOF

  ${BOLD}Done.${NC} Reboot to start:   ${BOLD}sudo reboot${NC}
  Then pick the ${BOLD}Hyprland${NC} session on the login screen
  (or, without one, log in on the console and type ${BOLD}start-hyprland${NC}).

  The first start sets the wallpaper and builds the colors from it.

  ${BOLD}Keys${NC} (Super = the Windows key)
    Super+Q          terminal (kitty)        Super+E         app launcher
    Super+W          browser (firefox)       Super+F         file manager
    Super+C          close window            Super+P         pick a wallpaper
    Super+K          all keybinds (edit)     Super+Alt+S     settings
    Super+M          monitors                Super+I         keyboard + mouse
    Super+N / B / A  network / bluetooth / audio
    Super+L          lock                    Super+Ctrl+P    power menu

  Your wallpapers go in ${BOLD}~/.config/quickshell/WallpaperApp/wallpapers/${NC}
  (videos and GIFs in its ${BOLD}animated/${NC} folder).
  Run ${BOLD}./install.sh --list${NC} to see the steps; any one can be run again
  on its own, e.g. ${BOLD}./install.sh --only packages${NC}.
EOF
