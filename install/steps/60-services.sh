#!/usr/bin/env bash
# Enable NetworkManager, Bluetooth, power profiles and a login screen (SDDM).
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

enabled() { systemctl is-enabled --quiet "$1" 2>/dev/null; }
installed_unit() { systemctl list-unit-files "$1" --no-legend 2>/dev/null | grep -q .; }

# enable_unit UNIT — enable at boot; start now too unless NOW=0.
enable_unit() {
    local unit=$1
    if ! installed_unit "$unit"; then
        warn "$unit isn't installed (run the packages step)"
        return 1
    fi
    if enabled "$unit"; then
        ok "$unit already enabled"
        return 0
    fi
    if [ "${NOW:-1}" = 1 ]; then
        as_root systemctl enable --now "$unit"
    else
        as_root systemctl enable "$unit"
    fi && ok "$unit enabled"
}

# --- network -----------------------------------------------------------------
# The NetworkPanel and the bar's network module talk to NetworkManager. Other
# network managers fight it over the interfaces, so they get switched off.
# Not started now: switching while this script downloads would drop the
# connection; it takes over after the reboot.
others=()
for unit in systemd-networkd.service dhcpcd.service iwd.service netctl.service connman.service; do
    enabled "$unit" && others+=("$unit")
done
if [ ${#others[@]} -gt 0 ] && ! enabled NetworkManager.service; then
    warn "Network is managed by: ${others[*]}"
    info "The network panel needs NetworkManager instead (Wi-Fi passwords are entered again there)."
    if ask_yn "Switch to NetworkManager after the reboot?" y; then
        for unit in "${others[@]}"; do as_root systemctl disable "$unit"; done
        NOW=0 enable_unit NetworkManager.service
        # systemd-networkd's wait-online would delay every boot without it
        enabled systemd-networkd-wait-online.service && as_root systemctl disable systemd-networkd-wait-online.service
    else
        warn "kept ${others[*]}: the network panel won't show connections"
    fi
else
    NOW=0 enable_unit NetworkManager.service
fi

# --- bluetooth, power ------------------------------------------------------------
enable_unit bluetooth.service
if enabled tlp.service; then
    warn "tlp is enabled: skipping power-profiles-daemon (they conflict); the bar's power profile menu stays empty"
else
    enable_unit power-profiles-daemon.service
fi

# --- login screen ------------------------------------------------------------
dm=""
for unit in sddm gdm lightdm ly greetd lxdm; do
    enabled "$unit.service" && { dm=$unit; break; }
done
if [ -n "$dm" ]; then
    ok "login screen: $dm (pick the Hyprland session there)"
elif ask_yn "Install a login screen (SDDM)? Without one you log in on the text console and type start-hyprland" y; then
    if [ -n "$(missing_packages sddm)" ]; then
        NOCONFIRM=()
        [ "$ASSUME_YES" = 1 ] && NOCONFIRM=(--noconfirm)
        as_root pacman -S --needed "${NOCONFIRM[@]}" sddm || die "installing sddm failed"
    fi
    # Not started now: it would take over this terminal.
    NOW=0 enable_unit sddm.service
    info "SDDM starts on the next boot; choose the \"Hyprland\" session there."
else
    info "after logging in on the console, start the desktop with: start-hyprland"
fi
exit 0
