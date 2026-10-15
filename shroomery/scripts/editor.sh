#!/usr/bin/env bash
# Open files in the configured text editor (settings/editor).
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

# shellcheck disable=SC2046
exec $(setting editor gnome-text-editor) "$@"
