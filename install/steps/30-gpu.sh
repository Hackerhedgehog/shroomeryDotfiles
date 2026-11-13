#!/usr/bin/env bash
# Detect the graphics card and install its driver (Mesa, or NVIDIA when asked).
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

have lspci || die "lspci not found (package pciutils): run the packages step first"

gpus=$(lspci -mm | grep -E '"(VGA compatible controller|3D controller|Display controller)"' || true)
if [ -z "$gpus" ]; then
    warn "no graphics card found by lspci: skipping drivers"
    exit 0
fi
while IFS= read -r line; do
    info "found: $(sed -E 's/^[^"]*"[^"]*" "([^"]*)" "([^"]*)".*/\1 \2/' <<<"$line")"
done <<<"$gpus"

NOCONFIRM=()
[ "$ASSUME_YES" = 1 ] && NOCONFIRM=(--noconfirm)

pkgs=(mesa)
grep -qi 'AMD\|ATI\|Advanced Micro' <<<"$gpus" && pkgs+=(vulkan-radeon)
grep -qi 'Intel' <<<"$gpus" && pkgs+=(vulkan-intel intel-media-driver)

# NVIDIA: the open kernel modules (Turing = GTX 16xx / RTX 20xx and newer).
# DKMS builds them for every installed kernel, which needs its headers.
nvidia=0
if grep -qi 'NVIDIA' <<<"$gpus"; then
    if pacman -Qq nvidia-utils >/dev/null 2>&1; then
        ok "NVIDIA driver already installed ($(pacman -Q nvidia-utils | cut -d' ' -f2))"
    else
        warn "An NVIDIA card needs the proprietary driver for Hyprland to run."
        info "This installs nvidia-open-dkms, for GTX 16xx / RTX 20xx and newer cards."
        info "Older cards (GTX 10xx and before) need a legacy driver instead:"
        info "https://wiki.archlinux.org/title/NVIDIA — answer no and install it yourself."
        if ask_yn "Install the NVIDIA driver?" y; then
            nvidia=1
            pkgs+=(nvidia-open-dkms nvidia-utils egl-wayland libva-nvidia-driver)
            for kernel in linux linux-lts linux-zen linux-hardened; do
                pacman -Qq "$kernel" >/dev/null 2>&1 && pkgs+=("$kernel-headers")
            done
        fi
    fi
fi

mapfile -t missing < <(missing_packages "${pkgs[@]}")
if [ ${#missing[@]} -gt 0 ]; then
    info "installing: ${missing[*]}"
    as_root pacman -S --needed "${NOCONFIRM[@]}" "${missing[@]}" || die "pacman failed"
fi
ok "graphics drivers installed"

# Hyprland's recommended NVIDIA environment. hypr/custom.lua is loaded by
# hyprland.lua when it exists and is ignored by git (it's per machine).
if [ "$nvidia" = 1 ] || pacman -Qq nvidia-utils >/dev/null 2>&1; then
    write_file "$REPO_DIR/hypr/custom.lua" <<'LUA'
-- Per-machine Hyprland settings (not in git). Written by install.sh for an
-- NVIDIA card: https://wiki.hypr.land/Nvidia/
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")
LUA
    [ "$nvidia" = 1 ] && warn "Reboot after the installer finishes so the NVIDIA driver loads."
fi
exit 0
