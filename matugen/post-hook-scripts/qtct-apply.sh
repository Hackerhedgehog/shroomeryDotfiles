#!/usr/bin/env bash
# After matugen writes qtct-colors.conf, point qt5ct/qt6ct at it, keep
# custom_palette on, and use Fusion so the QPalette is actually applied.
# Breeze on non-Plasma often keeps its own dark chrome while still taking
# WindowText from the scheme — that is dark-on-dark in light mode.
set -euo pipefail

SCHEME="$HOME/.config/qt6ct/colors/matugen.conf"
SCHEME5="$HOME/.config/qt5ct/colors/matugen.conf"

if [ -f "$SCHEME" ]; then
    mkdir -p "$(dirname "$SCHEME5")"
    cp -f "$SCHEME" "$SCHEME5"
fi

set_kv() {
    local conf="$1" key="$2" value="$3"
    if grep -qE "^${key}=" "$conf"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$conf"
    else
        if ! grep -qE '^\[Appearance\]' "$conf"; then
            printf '\n[Appearance]\n' >> "$conf"
        fi
        # Insert just after [Appearance]
        sed -i "/^\[Appearance\]/a ${key}=${value}" "$conf"
    fi
}

point_qtct() {
    local conf="$1"
    local scheme="$2"
    [ -f "$conf" ] || return 0
    [ -f "$scheme" ] || return 0

    set_kv "$conf" color_scheme_path "$scheme"
    set_kv "$conf" custom_palette true
    set_kv "$conf" style Fusion
}

point_qtct "$HOME/.config/qt6ct/qt6ct.conf" "$SCHEME"
point_qtct "$HOME/.config/qt5ct/qt5ct.conf" "$SCHEME5"
