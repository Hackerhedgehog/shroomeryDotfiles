#!/usr/bin/env bash
# Show/hide the battery panel (charge, power profile, idle and lid actions).
# Usage: toggle.sh [toggle|open|close|status]
exec "$(dirname "$(readlink -f "$0")")/../shared/toggle.sh" battery "$@"
