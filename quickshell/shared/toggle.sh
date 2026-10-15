#!/usr/bin/env bash
# Show/hide an app in the running Quickshell shell over IPC. Every app's
# toggle.sh is a one-line wrapper around this; it never starts a second shell.
#
#   shared/toggle.sh [-p CONFIG_DIR] TARGET [toggle|open|close|status]
#
# TARGET is the app's IPC target (see `qs ipc show`). -p addresses a separate
# Quickshell instance (OverviewApp runs as its own shell).
# The statusbar, dock and visualizer are not panels: open/close map to enable/disable.

set -euo pipefail

usage() {
    echo "Usage: $(basename "$0") [-p CONFIG_DIR] TARGET [toggle|open|close|status]" >&2
    exit 1
}

qs_args=()
if [ "${1:-}" = "-p" ]; then
    [ $# -ge 2 ] || usage
    qs_args=(-p "$2")
    shift 2
fi

target="${1:-}"
[ -n "$target" ] || usage
action="${2:-toggle}"

case "$target" in
    statusbar|dock) open_fn=enable; close_fn=disable; status_fn="" ;;
    visualizer)     open_fn=enable; close_fn=disable; status_fn=isActive ;;
    overview)       open_fn=open;   close_fn=close;   status_fn="" ;;
    *)              open_fn=open;   close_fn=close;   status_fn=isOpen ;;
esac

case "$action" in
    toggle|"")        fn=toggle ;;
    on|open|show)     fn=$open_fn ;;
    off|close|hide)   fn=$close_fn ;;
    status)
        [ -n "$status_fn" ] || { echo "'$target' has no status" >&2; exit 1; }
        fn=$status_fn ;;
    -h|--help|*)      usage ;;
esac

exec qs "${qs_args[@]}" ipc call "$target" "$fn"
