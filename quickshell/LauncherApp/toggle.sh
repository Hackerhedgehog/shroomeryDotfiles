#!/usr/bin/env bash
# Show/hide the application launcher.
# Usage: toggle.sh [toggle|open|close|status]
#        toggle.sh emoji    open on the emoji tab (close if already showing it)
if [ "${1:-}" = "emoji" ]; then
    exec qs ipc call launcher-mode toggle emoji
fi
exec "$(dirname "$(readlink -f "$0")")/../shared/toggle.sh" launcher "$@"
