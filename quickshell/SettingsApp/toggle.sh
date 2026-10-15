#!/usr/bin/env bash
# Show/hide the quick-settings panel.
# Usage: toggle.sh [toggle|open|close|status]
exec "$(dirname "$(readlink -f "$0")")/../shared/toggle.sh" settings "$@"
