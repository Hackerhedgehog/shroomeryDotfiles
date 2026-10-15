#!/usr/bin/env bash
# Show/hide the monitor layout panel.
# Usage: toggle.sh [toggle|open|close|status]
exec "$(dirname "$(readlink -f "$0")")/../shared/toggle.sh" monitors "$@"
