#!/usr/bin/env bash
# Show/hide the power panel (lock, suspend, logout, reboot, power off).
# Usage: toggle.sh [toggle|open|close|status]
exec "$(dirname "$(readlink -f "$0")")/../shared/toggle.sh" power "$@"
