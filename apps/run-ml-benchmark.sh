#!/bin/bash
# Run Jda vs Python ML benchmark side by side
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║          Jda vs Python — ML Training Benchmark                 ║"
echo "║  Both implement identical neural networks from scratch.        ║"
echo "║  Jda: compiled to native x86-64 by self-hosted compiler       ║"
echo "║  Python: CPython interpreter, pure Python (no NumPy)           ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# Build Jda binary if needed
if [ ! -f "$SCRIPT_DIR/jda-ml-demo" ]; then
    echo "Building Jda ML demo..."
    bash "$SCRIPT_DIR/build-ml-demo.sh"
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  RUNNING: Jda (native x86-64 binary)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

JDA_START=$(python3 -c "import time; print(int(time.monotonic()*1000))")
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v "$PROJECT_ROOT":/jda -w /jda jda-build ./apps/jda-ml-demo
JDA_END=$(python3 -c "import time; print(int(time.monotonic()*1000))")
JDA_TOTAL=$((JDA_END - JDA_START))

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  RUNNING: Python (CPython, pure Python, no NumPy)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

PY_START=$(python3 -c "import time; print(int(time.monotonic()*1000))")
python3 "$SCRIPT_DIR/ml-demo-python.py"
PY_END=$(python3 -c "import time; print(int(time.monotonic()*1000))")
PY_TOTAL=$((PY_END - PY_START))

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  RESULTS                                                       ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
printf "║  Jda total:    %6d ms                                      ║\n" "$JDA_TOTAL"
printf "║  Python total: %6d ms                                      ║\n" "$PY_TOTAL"
if [ "$JDA_TOTAL" -gt 0 ]; then
    SPEEDUP=$((PY_TOTAL * 10 / JDA_TOTAL))
    SPEEDUP_W=$((SPEEDUP / 10))
    SPEEDUP_F=$((SPEEDUP - SPEEDUP_W * 10))
    printf "║  Speedup:      %3d.%dx (Jda vs Python)                       ║\n" "$SPEEDUP_W" "$SPEEDUP_F"
fi
echo "╚══════════════════════════════════════════════════════════════════╝"
