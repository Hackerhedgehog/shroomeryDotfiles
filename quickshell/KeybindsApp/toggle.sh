#!/usr/bin/env bash
# Show/hide the keybinds editor.
# Usage: toggle.sh [toggle|open|close|status]
exec "$(dirname "$(readlink -f "$0")")/../shared/toggle.sh" keybinds "$@"
