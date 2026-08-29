#!/usr/bin/env bash
# Stage 1 conformance — thin wrapper around tools/run_tests.sh.
#
# This script used to re-implement the runner and got it wrong: it ignored the
# `<name>.include` sidecars that pull in a stdlib module, so every stdlib-backed
# test failed to compile, and it checked failure cases by grepping for the
# string "Parse error", which the compiler does not emit. tools/run_tests.sh is
# the maintained runner; defer to it.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

JDA1_BIN="${JDA1_BIN:-$ROOT_DIR/bootstrap/stage0/jda1}"

if [[ ! -x "$JDA1_BIN" ]]; then
  BOOTSTRAP="$ROOT_DIR/bootstrap/bin/jda1-bootstrap"
  STAGE1_SRC="$ROOT_DIR/bootstrap/stage1/jda1.jda"
  if [[ -x "$BOOTSTRAP" && -f "$STAGE1_SRC" ]]; then
    echo "[stage1-conformance] building Stage 1 compiler from bootstrap"
    "$BOOTSTRAP" "$STAGE1_SRC" "$JDA1_BIN"
    chmod +x "$JDA1_BIN"
  fi
fi

if [[ ! -x "$JDA1_BIN" ]]; then
  echo "[stage1-conformance] SKIP: Stage 1 compiler not found at $JDA1_BIN"
  exit 0
fi

exec bash tools/run_tests.sh
