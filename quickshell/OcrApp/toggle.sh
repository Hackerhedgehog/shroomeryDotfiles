#!/usr/bin/env bash
# Show/hide the text extractor panel, or start a capture.
# Usage: toggle.sh [toggle|open|close|status]
#        toggle.sh capture    select a screen area and extract its text (SUPER+ALT+A)
if [ "${1:-}" = "capture" ]; then
    exec qs ipc call ocr-capture run
fi
exec "$(dirname "$(readlink -f "$0")")/../shared/toggle.sh" ocr "$@"
