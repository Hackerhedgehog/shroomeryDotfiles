#!/usr/bin/env bash
# Launch the configured terminal (settings/terminal), passing any arguments on.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

# shellcheck disable=SC2046
exec $(terminal_cmd) "$@"
