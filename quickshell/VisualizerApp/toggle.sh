#!/usr/bin/env bash
# Visualizer: toggle = Super+Alt+V (stop if running, else open/close the setup panel);
# open = start right away with the saved settings; close = stop; status = running?
# Usage: toggle.sh [toggle|open|close|status]
exec "$(dirname "$(readlink -f "$0")")/../shared/toggle.sh" visualizer "$@"
