#!/bin/bash
# Build jda-httpd — HTTP server written in Jda
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Concatenate stdlib dependencies into a single include file
cat "$PROJECT_ROOT/stdlib/prelude.jda" \
    > /tmp/httpd_stdlib.jda

# Compile
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v "$PROJECT_ROOT":/jda -v /tmp/httpd_stdlib.jda:/tmp/httpd_stdlib.jda \
  -w /jda jda-build ./bootstrap/stage0/jda1 build \
  --include /tmp/httpd_stdlib.jda \
  apps/jda-httpd.jda -o apps/jda-httpd 2>&1 | tail -3

echo "Built: apps/jda-httpd ($(wc -c < "$SCRIPT_DIR/jda-httpd") bytes)"
