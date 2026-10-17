#!/usr/bin/env bash
# Calibrated pink-noise test bursts for the dynamic loudness processor.
# Pink noise rather than a sine tone: a pure tone makes it very hard to hear
# what a compressor is doing to programme material.

set -euo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/loudness-tones"
LEVELS=(-45 -35 -25 -15 -3)
NAMES=(very-quiet quiet medium loud very-loud)

generate() {
    mkdir -p "$CACHE"
    for i in "${!LEVELS[@]}"; do
        out="$CACHE/${NAMES[$i]}.wav"
        [ -f "$out" ] && continue
        # 1.2 s of seeded pink noise, then faded so the burst does not click.
        # The seed ensures reproducible output across machines and ffmpeg
        # versions. The source produces a peak ~4.8 dB below 0 dB after the
        # lowpass/highpass filters, so +7.2 dB compensation (applied first)
        # brings it to 0 dB, then per-tone volume gains produce the target
        # levels.
        ffmpeg -hide_banner -loglevel error -y \
            -f lavfi -i "anoisesrc=d=1.2:c=pink:a=1.0:r=48000:s=42" \
            -af "lowpass=f=16000,highpass=f=40,volume=7.2dB,volume=${LEVELS[$i]}dB,afade=t=in:st=0:d=0.05,afade=t=out:st=1.15:d=0.05" \
            -ac 2 -ar 48000 -c:a pcm_s16le "$out"
    done
}

usage() {
    echo "Usage: $0 play <0-4>" >&2
    exit 1
}

case "${1:-}" in
    play)
        idx="${2:-}"
        [[ "$idx" =~ ^[0-4]$ ]] || usage
        generate
        exec paplay "$CACHE/${NAMES[$idx]}.wav"
        ;;
    generate)
        generate
        ;;
    *)
        usage
        ;;
esac
