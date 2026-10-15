#!/usr/bin/env bash
# Compile the visualizer shader (visualizer.frag -> visualizer.frag.qsb).
# Run after editing visualizer.frag; the .qsb is kept next to it.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
/usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o visualizer.frag.qsb visualizer.frag
echo "built $(pwd)/visualizer.frag.qsb"
echo "Qt caches shaders per process: restart qs (a hot reload keeps the old one)."
