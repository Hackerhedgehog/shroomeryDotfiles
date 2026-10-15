#!/usr/bin/env bash
# Start/stop the background listeners in listeners/.
#   listeners.sh --startall | --stopall | --restartall
#   listeners.sh --start NAME | --stop NAME | --restart NAME
# NAME is a script in listeners/ without .sh (gtk-theme, low-battery).

LISTENER_DIR="$HOME/.config/shroomery/listeners"

listener_path() { echo "$LISTENER_DIR/$1.sh"; }

all_listeners() {
    for f in "$LISTENER_DIR"/*.sh; do
        basename "$f" .sh
    done
}

start_listener() {
    local path
    path=$(listener_path "$1")
    if [ ! -x "$path" ]; then
        echo "Error: listener '$1' not found or not executable: $path"
        return 1
    fi
    if pgrep -f "$path" >/dev/null; then
        echo "Listener '$1' is already running."
        return 0
    fi
    nohup "$path" >/dev/null 2>&1 &
    echo "Listener '$1' started."
}

stop_listener() {
    local path pid
    path=$(listener_path "$1")
    pid=$(pgrep -f "$path")
    if [ -z "$pid" ]; then
        echo "Listener '$1' is not running."
        return 0
    fi
    # shellcheck disable=SC2086
    kill $pid
    sleep 1
    # shellcheck disable=SC2086
    pgrep -f "$path" >/dev/null && kill -9 $pid
    echo "Listener '$1' stopped."
}

case "${1:-}" in
    --startall)   for l in $(all_listeners); do start_listener "$l"; done ;;
    --stopall)    for l in $(all_listeners); do stop_listener "$l"; done ;;
    --restartall) for l in $(all_listeners); do stop_listener "$l"; start_listener "$l"; done ;;
    --start)      start_listener "${2:?listener name}" ;;
    --stop)       stop_listener "${2:?listener name}" ;;
    --restart)    stop_listener "${2:?listener name}"; start_listener "$2" ;;
    *)
        echo "Usage: $0 --startall | --stopall | --restartall | --start NAME | --stop NAME | --restart NAME"
        echo "Listeners: $(all_listeners | tr '\n' ' ')"
        exit 1
        ;;
esac
