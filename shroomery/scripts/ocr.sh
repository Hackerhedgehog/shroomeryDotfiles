#!/usr/bin/env bash
# Text extraction (OCR) for quickshell/OcrApp: freeze the screen, let the user
# drag a region, and print the text tesseract reads in it to stdout.
#
#   ocr.sh [--lang CODE]    capture + OCR
#   ocr.sh --list-langs     the installed tesseract languages, one per line
#
# Exit codes: 0 text printed (may be empty), 1 selection cancelled or timed
# out, 2 a dependency is missing, 3 capturing or reading the text failed.
#
# The language defaults to settings/ocr-language, else eng.
source "$(dirname "$(readlink -f "$0")")/../lib.sh"

set -Eeuo pipefail

SLURP_TIMEOUT=30
DEPS=(grim slurp magick tesseract hyprpicker timeout)

# osd (orientation/script detection) and equ (equations) are not languages.
list_langs() {
    tesseract --list-langs 2>/dev/null | tail -n +2 | grep -vxE 'osd|equ' || true
}

lang=""
case "${1:-}" in
    --list-langs) list_langs; exit 0 ;;
    --lang) lang="${2:-}" ;;
    "") ;;
    *) error "Usage: $(basename "$0") [--lang CODE | --list-langs]"; exit 2 ;;
esac
[ -n "$lang" ] || lang=$(setting ocr-language eng)

for dep in "${DEPS[@]}"; do
    command -v "$dep" >/dev/null 2>&1 || { error "Missing dependency: $dep"; exit 2; }
done

# Freeze the screen while selecting, so moving content can be captured.
hyprpicker -r -z &
picker=$!
trap 'kill "$picker" 2>/dev/null || true' EXIT
sleep 0.1

# slurp reads predefined boxes from stdin whenever it is not a TTY, so with
# the pipe Quickshell gives it, it would wait there and never show.
region=$(timeout "$SLURP_TIMEOUT" slurp -b "#00000080" -c "#888888ff" -w 1 </dev/null) || exit 1
[ -n "$region" ] || exit 1

shot=$(mktemp --suffix=.png)
trap 'kill "$picker" 2>/dev/null || true; rm -f "$shot"' EXIT

# grim captures the frozen frame; unfreeze before the (slower) OCR.
grim -g "$region" "$shot" || { error "Capturing the selected area failed"; exit 3; }
kill "$picker" 2>/dev/null || true

if ! magick "$shot" -colorspace Gray -normalize -contrast-stretch 2% -sharpen 0x1.0 -resize 200% png:- \
    | tesseract - stdout -l "$lang" --psm 6 2>/dev/null; then
    error "Reading text from the selected area failed"
    exit 3
fi
