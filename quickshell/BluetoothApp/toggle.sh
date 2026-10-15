#!/usr/bin/env bash
# Show/hide the Bluetooth panel.
# Usage: toggle.sh [toggle|open|close|status]
exec "$(dirname "$(readlink -f "$0")")/../shared/toggle.sh" bluetooth "$@"
