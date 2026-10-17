#!/usr/bin/env bash
# Show/hide the dashboard (the status bar grows into it from the clock).
# Usage: toggle.sh [toggle|open|close|status]
exec "$(dirname "$(readlink -f "$0")")/../shared/toggle.sh" dashboard "$@"
