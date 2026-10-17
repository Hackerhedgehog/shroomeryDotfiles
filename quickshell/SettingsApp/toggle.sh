#!/usr/bin/env bash
# Show/hide the settings window.
# Usage: toggle.sh [toggle|open|close|status]
exec "$(dirname "$(readlink -f "$0")")/../shared/toggle.sh" settings "$@"
