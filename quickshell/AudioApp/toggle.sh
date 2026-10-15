#!/usr/bin/env bash
# Show/hide the audio panel (outputs, mixer, inputs, loudness).
# Usage: toggle.sh [toggle|open|close|status]
exec "$(dirname "$(readlink -f "$0")")/../shared/toggle.sh" audio "$@"
