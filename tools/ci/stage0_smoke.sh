#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGE0_DIR="$ROOT_DIR/bootstrap/stage0"

echo "[stage0-smoke] building Stage 0 compiler"
make -C "$STAGE0_DIR" all

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

OUT_BIN="$WORK_DIR/hello_out"
OUT_LOG="$WORK_DIR/hello_stdout.txt"
ERR_LOG="$WORK_DIR/hello_stderr.txt"

echo "[stage0-smoke] compiling hello example"
"$STAGE0_DIR/jda0" "$ROOT_DIR/examples/hello.jda" "$OUT_BIN" >"$OUT_LOG" 2>"$ERR_LOG"

chmod +x "$OUT_BIN"
"$OUT_BIN" >"$WORK_DIR/hello_run.txt" 2>"$WORK_DIR/hello_run_err.txt"

if ! grep -q "Hello Bare Metal" "$WORK_DIR/hello_run.txt"; then
  echo "[stage0-smoke] FAIL: hello output mismatch"
  echo "--- stdout ---"
  cat "$WORK_DIR/hello_run.txt"
  echo "--- stderr ---"
  cat "$WORK_DIR/hello_run_err.txt"
  exit 1
fi

echo "[stage0-smoke] checking parser failure path"
BAD_SRC="$WORK_DIR/bad.jda"
cat >"$BAD_SRC" <<'EOF'
fn main() {
    let x = 42
}
EOF

if "$STAGE0_DIR/jda0" "$BAD_SRC" "$WORK_DIR/bad_out" >"$WORK_DIR/bad_stdout.txt" 2>"$WORK_DIR/bad_stderr.txt"; then
  echo "[stage0-smoke] FAIL: expected compile failure for source without print()"
  exit 1
fi

if ! grep -q "no print() call found" "$WORK_DIR/bad_stderr.txt"; then
  echo "[stage0-smoke] FAIL: expected parse error message not found"
  echo "--- stderr ---"
  cat "$WORK_DIR/bad_stderr.txt"
  exit 1
fi

echo "[stage0-smoke] PASS"
