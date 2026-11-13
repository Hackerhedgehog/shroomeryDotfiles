#!/usr/bin/env bash
# Check the system (Arch, internet, sudo) and ask for the sudo password once.
set -uo pipefail
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

[ -f /etc/arch-release ] && have pacman || die "This installer is for Arch Linux (pacman not found)."
ok "Arch Linux"

[ "$EUID" -ne 0 ] || die "Run as your normal user, not root."
ok "running as $USER"

if curl -fsS --max-time 15 -o /dev/null https://archlinux.org; then
    ok "internet works"
else
    die "No internet connection (couldn't reach archlinux.org). Connect first, e.g. with 'nmtui' or 'iwctl'."
fi

# A bare Arch install may have no sudo at all, or a user that may not use it.
# Fix that once through root's password (su), with a rule for this user only:
# a new wheel membership would only count after logging in again.
setup_sudo() {
    warn "sudo isn't set up for $USER yet."
    ask_yn "Set it up now? (asks for the ROOT password)" y || die "sudo is needed to install packages."
    local rule="$USER ALL=(ALL:ALL) ALL" file="/etc/sudoers.d/10-installer-$USER"
    su -c "set -e
        pacman -S --needed --noconfirm sudo
        printf '%s\\n' '$rule' > '$file'
        chmod 440 '$file'
        visudo -cf '$file'" root || die "Setting up sudo failed."
    ok "sudo set up ($file)"
}

if [ "$DRY_RUN" = 1 ]; then
    have sudo || info "[dry-run] would install sudo and allow $USER to use it (via su)"
    info "[dry-run] skipping the sudo password prompt"
else
    have sudo || setup_sudo
    info "Some steps need root. Enter your password for sudo:"
    if ! sudo -v; then
        setup_sudo
        sudo -v || die "sudo still fails."
    fi
    ok "sudo works"
fi

if [ "$(readlink -f "$CONFIG_DIR/hypr" 2>/dev/null)" = "$REPO_DIR/hypr" ]; then
    info "already installed here before: your settings are kept unless you choose otherwise"
fi
