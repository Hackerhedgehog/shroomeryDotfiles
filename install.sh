#!/usr/bin/env bash
# Install shroomeryDotfiles on an Arch Linux system: packages, GPU driver,
# ~/.config symlinks, first-run config files and services. Run it as your
# normal user from wherever you cloned the repo; it asks for your password
# (sudo) in the terminal when it needs root.
#
# Usage: ./install.sh [options]
#   -y, --yes          don't ask, take every default answer
#   -n, --dry-run      show what would happen, change nothing
#   --only STEP[,…]    run only these steps
#   --skip STEP[,…]    run every step except these
#   -l, --list         list the steps and exit
#   -h, --help         this help
#
# Each step is a script in install/steps/ (run in file-name order) and can be
# run again on its own, e.g. `./install.sh --only link`. Safe to re-run.
set -uo pipefail

source "$(dirname "$(readlink -f "$0")")/install/lib.sh"

STEPS_DIR="$INSTALL_DIR/steps"
ONLY="" SKIP="" LIST=0

usage() { sed -n '2,/^set /{ /^set /d; s/^# \{0,1\}//; p }' "$0"; }

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)     ASSUME_YES=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        --only)       ONLY="${2:?--only needs a step list}"; shift ;;
        --only=*)     ONLY="${1#*=}" ;;
        --skip)       SKIP="${2:?--skip needs a step list}"; shift ;;
        --skip=*)     SKIP="${1#*=}" ;;
        -l|--list)    LIST=1 ;;
        -h|--help)    usage; exit 0 ;;
        *)            usage >&2; echo >&2; die "unknown option: $1" ;;
    esac
    shift
done

# name of a step file: 20-packages.sh -> packages
step_name() { local b; b=$(basename "$1" .sh); echo "${b#*-}"; }
# its description: the first comment line after the shebang
step_desc() { sed -n '2s/^# *//p' "$1"; }

mapfile -t STEP_FILES < <(find "$STEPS_DIR" -maxdepth 1 -name '[0-9]*-*.sh' | sort)
[ ${#STEP_FILES[@]} -gt 0 ] || die "no steps found in $STEPS_DIR"

if [ "$LIST" = 1 ]; then
    for f in "${STEP_FILES[@]}"; do
        printf '  %-10s %s\n' "$(step_name "$f")" "$(step_desc "$f")"
    done
    exit 0
fi

in_list() { [[ ",$2," == *",$1,"* ]]; }

# Check --only/--skip names before doing anything.
for name in ${ONLY//,/ } ${SKIP//,/ }; do
    found=0
    for f in "${STEP_FILES[@]}"; do [ "$(step_name "$f")" = "$name" ] && found=1; done
    [ $found = 1 ] || die "no step named '$name' (see ./install.sh --list)"
done

SELECTED=()
for f in "${STEP_FILES[@]}"; do
    name=$(step_name "$f")
    [ -n "$ONLY" ] && ! in_list "$name" "$ONLY" && continue
    [ -n "$SKIP" ] && in_list "$name" "$SKIP" && continue
    SELECTED+=("$f")
done

[ "$EUID" -ne 0 ] || die "Run this as your normal user, not root: it asks for sudo itself when needed."

# "Fresh" = this repo wasn't linked into ~/.config yet. Machine-specific
# settings (monitors, keyboard layout, …) are only reset by default then.
SHROOMERY_FRESH=1
if [ "$(readlink -f "$CONFIG_DIR/hypr" 2>/dev/null)" = "$REPO_DIR/hypr" ]; then
    SHROOMERY_FRESH=0
fi
export ASSUME_YES DRY_RUN SHROOMERY_FRESH

printf '%s' "$BOLD"
cat <<'EOF'

   ┌─┐┬ ┬┬─┐┌─┐┌─┐┌┬┐┌─┐┬─┐┬ ┬
   └─┐├─┤├┬┘│ ││ ││││├┤ ├┬┘└┬┘
   └─┘┴ ┴┴└─└─┘└─┘┴ ┴└─┘┴└─ ┴   dotfiles installer
EOF
printf '%s\n' "$NC"
info "repo:  ${REPO_DIR/#$HOME/\~}"
info "steps: $(for f in "${SELECTED[@]}"; do printf '%s ' "$(step_name "$f")"; done)"
[ "$DRY_RUN" = 1 ] && warn "dry run: nothing will be changed"
[ "$ASSUME_YES" = 1 ] && info "taking the default answer to every question"

# Keep the sudo timestamp alive while the steps run (sudo asks once, in the
# preflight step or the first step that needs it).
SUDO_KEEPALIVE_PID=""
start_sudo_keepalive() {
    [ "$DRY_RUN" = 1 ] && return
    [ -n "$SUDO_KEEPALIVE_PID" ] && return
    sudo -n true 2>/dev/null || return
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
    SUDO_KEEPALIVE_PID=$!
}
cleanup() { [ -n "$SUDO_KEEPALIVE_PID" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null; }
trap cleanup EXIT
trap 'echo; die "interrupted"' INT TERM

DONE=() FAILED=()
for f in "${SELECTED[@]}"; do
    name=$(step_name "$f")
    header "$name — $(step_desc "$f")"
    if bash "$f"; then
        DONE+=("$name")
    else
        status=$?
        FAILED+=("$name")
        error "step '$name' failed (exit $status)"
        if [ "$ASSUME_YES" = 1 ] || ! ask_yn "Continue with the next step anyway?" n; then
            break
        fi
    fi
    start_sudo_keepalive
done

header "Summary"
[ ${#DONE[@]} -gt 0 ] && ok "done: ${DONE[*]}"
if [ ${#FAILED[@]} -gt 0 ]; then
    error "failed: ${FAILED[*]}"
    info "fix the problem above and run it again: ./install.sh --only ${FAILED[0]}"
    exit 1
fi
