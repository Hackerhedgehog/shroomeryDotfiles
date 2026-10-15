#!/usr/bin/env bash
# Interactive system update (pacman/AUR or dnf, then flatpak). Run inside a
# terminal; install-updates.sh opens one.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

has() { command -v "$1" &> /dev/null; }

sleep 1
clear
has figlet && figlet -f smslant "Updates"
echo
primary=$(palette_color primary)
on_primary=$(palette_color on_primary)
on_surface=$(palette_color on_surface)
if gum confirm ${primary:+--selected.background=$primary} ${on_primary:+--selected.foreground=$on_primary} \
        ${on_surface:+--prompt.foreground=$on_surface} "DO YOU WANT TO START THE UPDATE NOW?"; then
    echo
    echo ":: Update started..."
elif [ $? -eq 130 ]; then
    exit 130
else
    echo
    echo ":: Update canceled."
    exit
fi

if has pacman; then
    if ! has yay && has paru; then
        paru -Syu --noconfirm
    else
        yay
    fi
elif has dnf; then
    sudo dnf upgrade
else
    echo ":: ERROR - Platform not supported"
    echo "Press [ENTER] to close."
    read -r
fi
echo

if has flatpak; then
    echo ":: Searching for Flatpak updates..."
    flatpak update
    echo
fi

# Refresh the statusbar update counter.
qs ipc call updates refresh >/dev/null 2>&1 || true

echo ":: Update complete! Press [ENTER] to close."
read -r
