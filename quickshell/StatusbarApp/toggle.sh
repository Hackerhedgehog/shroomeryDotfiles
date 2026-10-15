#!/usr/bin/env bash
# Turn the statusbar on/off (open/close = enable/disable; persisted in shroomery/settings/statusbar.json).
# Usage: toggle.sh [toggle|open|close|status]
exec "$(dirname "$(readlink -f "$0")")/../shared/toggle.sh" statusbar "$@"
