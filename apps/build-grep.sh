#!/bin/bash
# Build jda-grep — the first real application written in Jda
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Concatenate stdlib dependencies into a single include file
cat "$PROJECT_ROOT/stdlib/prelude.jda" \
    "$PROJECT_ROOT/stdlib/fs.jda" \
    "$PROJECT_ROOT/stdlib/file_io.jda" \
    > /tmp/grep_stdlib.jda

# Compile
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v "$PROJECT_ROOT":/jda -v /tmp/grep_stdlib.jda:/tmp/grep_stdlib.jda \
  -w /jda jda-build ./bootstrap/stage0/jda1 build \
  --include /tmp/grep_stdlib.jda \
  apps/jda-grep.jda -o apps/jda-grep 2>&1 | tail -3

echo "Built: apps/jda-grep ($(wc -c < "$SCRIPT_DIR/jda-grep") bytes)"
