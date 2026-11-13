#!/usr/bin/env bash
# Install the packages in install/packages/ (pacman, then the AUR via yay/paru).
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

mapfile -t REPO_PKGS < <(read_list "$INSTALL_DIR/packages/pacman.txt")
mapfile -t AUR_PKGS < <(read_list "$INSTALL_DIR/packages/aur.txt")

NOCONFIRM=()
[ "$ASSUME_YES" = 1 ] && NOCONFIRM=(--noconfirm)

# --- official repositories ---------------------------------------------------
mapfile -t missing < <(missing_packages "${REPO_PKGS[@]}")
if [ ${#missing[@]} -eq 0 ]; then
    ok "all ${#REPO_PKGS[@]} repository packages are installed"
    info "updating the system first (pacman -Syu)"
    as_root pacman -Syu "${NOCONFIRM[@]}" || die "pacman -Syu failed"
else
    info "${#missing[@]} of ${#REPO_PKGS[@]} repository packages to install:"
    printf '%s\n' "${missing[@]}" | column -c "${COLUMNS:-80}" | sed 's/^/      /'
    [ "$ASSUME_YES" = 1 ] || info "pacman may ask which provider to use for a few of them: Enter takes the default."
    # -Syu with the install: Arch doesn't support installing on a stale system.
    as_root pacman -Syu --needed "${NOCONFIRM[@]}" "${missing[@]}" || die "pacman failed"
    ok "repository packages installed"
fi

# --- AUR helper --------------------------------------------------------------
helper=$(aur_helper)
if [ -z "$helper" ]; then
    info "no AUR helper found: building yay-bin from the AUR"
    if [ "$DRY_RUN" = 1 ]; then
        info "[dry-run] git clone https://aur.archlinux.org/yay-bin.git && makepkg -si"
        helper=yay
    else
        build_dir=$(mktemp -d)
        trap 'rm -rf "$build_dir"' EXIT
        git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$build_dir/yay-bin" \
            || die "cloning yay-bin failed"
        (cd "$build_dir/yay-bin" && makepkg -si --noconfirm) || die "building yay-bin failed"
        helper=yay
        ok "yay installed"
    fi
else
    ok "AUR helper: $helper"
fi

# --- AUR packages ------------------------------------------------------------
mapfile -t missing < <(missing_packages "${AUR_PKGS[@]}")
if [ ${#missing[@]} -eq 0 ]; then
    ok "all ${#AUR_PKGS[@]} AUR packages are installed"
    exit 0
fi
info "AUR packages to build: ${missing[*]}"
case "$helper" in
    yay)  flags=(--answerclean None --answerdiff None --answeredit None --removemake) ;;
    paru) flags=(--skipreview --removemake) ;;
esac
run "$helper" -S --needed "${flags[@]}" "${NOCONFIRM[@]}" "${missing[@]}" || die "$helper failed"
ok "AUR packages installed"
