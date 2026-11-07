#!/usr/bin/env bash
# Show/hide the date & time panel (clock, timezone, formats, language).
# Usage: toggle.sh [toggle|open|close|status]
exec "$(dirname "$(readlink -f "$0")")/../shared/toggle.sh" time "$@"
