#!/usr/bin/env bash
# Open a floating terminal running system-update.sh.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

exec $(terminal_cmd) --class dotfiles-floating -e "$SHROOMERY_SCRIPTS/system-update.sh"
