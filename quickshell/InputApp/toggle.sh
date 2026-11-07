#!/usr/bin/env bash
# Show/hide the input panel (keyboard layout, mouse speed).
# Usage: toggle.sh [toggle|open|close|status]
exec "$(dirname "$(readlink -f "$0")")/../shared/toggle.sh" input "$@"
