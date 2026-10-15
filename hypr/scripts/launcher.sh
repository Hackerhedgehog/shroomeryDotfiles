#!/usr/bin/env bash

# -----------------------------------------------------
# Load Launcher
# -----------------------------------------------------
launcher=$(head -n 1 "$HOME/.config/shroomery/settings/launcher" 2>/dev/null || echo quickshell)

# Use the Quickshell launcher (quickshell/LauncherApp)
_launch_quickshell() {
    "$HOME/.config/quickshell/LauncherApp/toggle.sh" toggle
}

# Use Walker
_launch_walker() {
    $HOME/.config/walker/launch.sh --height 500
}

case "$launcher" in
    walker) _launch_walker ;;
    *)      _launch_quickshell ;;
esac
