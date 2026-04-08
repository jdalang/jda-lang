#!/bin/bash
# Build jda-ml-demo — ML training benchmark in pure Jda
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Compile (time.jda needed for benchmarking)
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v "$PROJECT_ROOT":/jda \
  -w /jda jda-build ./bootstrap/stage0/jda1 build \
  --include stdlib/time.jda \
  apps/jda-ml-demo.jda -o apps/jda-ml-demo 2>&1 | tail -3

echo "Built: apps/jda-ml-demo ($(wc -c < "$SCRIPT_DIR/jda-ml-demo") bytes)"
