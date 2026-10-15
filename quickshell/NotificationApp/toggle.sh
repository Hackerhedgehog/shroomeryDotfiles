#!/usr/bin/env bash
# Show/hide the notification panel.
# Usage: toggle.sh [toggle|open|close|status]
exec "$(dirname "$(readlink -f "$0")")/../shared/toggle.sh" notifications "$@"
