#!/usr/bin/env bash
# Turn the dock on/off (open/close = enable/disable; persisted in shroomery/settings/dock.json).
# Usage: toggle.sh [toggle|open|close|status]
exec "$(dirname "$(readlink -f "$0")")/../shared/toggle.sh" dock "$@"
