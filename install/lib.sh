#!/usr/bin/env bash
# Shared helpers for install.sh and every install/steps/*.sh. Source it:
#   source "$(dirname "$(readlink -f "$0")")/../lib.sh"
#
# Environment (set by install.sh, all optional when a step runs by itself):
#   ASSUME_YES=1        take every default answer, pass --noconfirm to pacman
#   DRY_RUN=1           print what would change instead of changing it
#   SHROOMERY_FRESH=1   these dotfiles were not linked into ~/.config before
#                       this run (machine-specific settings get reset)

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$INSTALL_DIR/.." && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
# The parts that are symlinked into ~/.config, one directory each in the repo.
LINKED_PARTS=(hypr quickshell shroomery matugen)

: "${ASSUME_YES:=0}"
: "${DRY_RUN:=0}"
# Without a terminal nobody can answer, so take the defaults.
[ -t 0 ] || ASSUME_YES=1

if [ -t 1 ]; then
    BOLD=$'\033[1m' DIM=$'\033[2m' RED=$'\033[0;31m' GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m' BLUE=$'\033[1;34m' NC=$'\033[0m'
else
    BOLD="" DIM="" RED="" GREEN="" YELLOW="" BLUE="" NC=""
fi

header() { printf '\n%s==>%s %s%s%s\n' "$BLUE" "$NC" "$BOLD" "$*" "$NC"; }
info()   { printf '  %s->%s %s\n' "$BLUE" "$NC" "$*"; }
ok()     { printf '  %s✓%s %s\n' "$GREEN" "$NC" "$*"; }
warn()   { printf '  %s!%s %s\n' "$YELLOW" "$NC" "$*" >&2; }
error()  { printf '  %s✗ %s%s\n' "$RED" "$*" "$NC" >&2; }
die()    { error "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# ask_yn QUESTION DEFAULT(y|n) — 0 for yes. Takes DEFAULT under ASSUME_YES.
ask_yn() {
    local question=$1 default=${2:-n} hint reply
    [ "$default" = y ] && hint="Y/n" || hint="y/N"
    if [ "$ASSUME_YES" = 1 ]; then
        printf '  %s?%s %s [%s] %s(%s)%s\n' "$YELLOW" "$NC" "$question" "$hint" "$DIM" "$default" "$NC"
        [ "$default" = y ]
        return
    fi
    while true; do
        read -r -p "  ${YELLOW}?${NC} $question [$hint] " reply
        case "${reply,,}" in
            "")      [ "$default" = y ]; return ;;
            y|yes)   return 0 ;;
            n|no)    return 1 ;;
        esac
    done
}

# ask QUESTION DEFAULT — prints the answer (DEFAULT when empty or under ASSUME_YES).
ask() {
    local question=$1 default=$2 reply=""
    if [ "$ASSUME_YES" = 1 ]; then
        printf '  %s?%s %s [%s]\n' "$YELLOW" "$NC" "$question" "$default" >&2
    else
        read -r -p "  ${YELLOW}?${NC} $question [$default] " reply
    fi
    printf '%s\n' "${reply:-$default}"
}

# run CMD... — run a command that changes the user's files (printed under DRY_RUN).
run() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '  %s[dry-run]%s %s\n' "$DIM" "$NC" "$*"
        return 0
    fi
    "$@"
}

# as_root CMD... — run a command with sudo (asks for the password in the terminal).
as_root() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '  %s[dry-run]%s sudo %s\n' "$DIM" "$NC" "$*"
        return 0
    fi
    sudo "$@"
}

# write_file PATH — write stdin to PATH (creating its directory). Leaves an
# existing file alone unless FORCE=1 is set for the call.
write_file() {
    local path=$1 content
    content=$(cat)
    if [ -e "$path" ] && [ "${FORCE:-0}" != 1 ]; then
        info "keeping existing ${path/#$HOME/\~}"
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        printf '  %s[dry-run]%s write %s\n' "$DIM" "$NC" "${path/#$HOME/\~}"
        return 0
    fi
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
    ok "wrote ${path/#$HOME/\~}"
}

# backup PATH — move PATH aside to PATH.bak-YYYYmmdd-HHMMSS and print the new name.
backup() {
    local path=$1 dest
    dest="$path.bak-$(date +%Y%m%d-%H%M%S)"
    run mv "$path" "$dest"
    printf '%s\n' "$dest"
}

# read_list FILE — the package names in FILE (one per line, # comments).
read_list() {
    sed -e 's/#.*//' -e 's/[[:space:]]//g' "$1" | grep -v '^$'
}

# missing_packages PKG... — the ones pacman can't satisfy yet (installed
# packages and anything that provides them count as present).
missing_packages() {
    [ $# -gt 0 ] || return 0
    pacman -T "$@" 2>/dev/null || true
}

# The AUR helper that is installed (yay or paru), or nothing.
aur_helper() {
    local h
    for h in yay paru; do
        have "$h" && { echo "$h"; return; }
    done
}
