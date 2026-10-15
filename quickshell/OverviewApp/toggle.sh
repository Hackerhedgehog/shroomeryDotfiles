#!/usr/bin/env bash
# Show/hide the workspace overview (runs as its own Quickshell instance,
# started by shroomery/scripts/autostart.sh).
# Usage: toggle.sh [toggle|open|close]
# The instance is addressed by the path it was started with (not the resolved
# symlink target), so use the ~/.config path here and in autostart.sh.
exec "$HOME/.config/quickshell/shared/toggle.sh" -p "$HOME/.config/quickshell/OverviewApp" overview "$@"
