#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUITE_DIR="$ROOT_DIR/tests/conformance/stage1"
PASS_DIR="$SUITE_DIR/pass"
FAIL_DIR="$SUITE_DIR/fail"
JDA1_BIN="${JDA1_BIN:-/tmp/jda1}"

if [[ ! -x "$JDA1_BIN" ]]; then
  STAGE0_BIN="$ROOT_DIR/bootstrap/stage0/jda0"
  STAGE1_SRC="$ROOT_DIR/bootstrap/stage1/jda1.jda"
  if [[ -x "$STAGE0_BIN" && -f "$STAGE1_SRC" ]]; then
    echo "[stage1-conformance] bootstrapping Stage1 binary via Stage0"
    "$STAGE0_BIN" "$STAGE1_SRC" "$JDA1_BIN"
    chmod +x "$JDA1_BIN"
  fi
fi

if [[ ! -x "$JDA1_BIN" ]]; then
  echo "[stage1-conformance] SKIP: Stage 1 compiler binary not found at $JDA1_BIN"
  exit 0
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

pass_count=0
fail_count=0

echo "[stage1-conformance] running pass cases"
for src in "$PASS_DIR"/*.jda; do
  base="$(basename "$src" .jda)"
  out_bin="$WORK_DIR/${base}.out"
  run_out="$WORK_DIR/${base}.stdout"
  expected="$PASS_DIR/${base}.expected"

  "$JDA1_BIN" "$src" "$out_bin" >"$WORK_DIR/${base}.compile.stdout" 2>"$WORK_DIR/${base}.compile.stderr"
  chmod +x "$out_bin"
  "$out_bin" >"$run_out" 2>"$WORK_DIR/${base}.run.stderr"

  if ! cmp -s "$run_out" "$expected"; then
    echo "[stage1-conformance] FAIL(pass): $base output mismatch"
    echo "--- expected ---"
    cat "$expected"
    echo "--- actual ---"
    cat "$run_out"
    exit 1
  fi

  pass_count=$((pass_count + 1))
done

echo "[stage1-conformance] running fail cases"
for src in "$FAIL_DIR"/*.jda; do
  base="$(basename "$src" .jda)"
  out_bin="$WORK_DIR/${base}.out"

  set +e
  "$JDA1_BIN" "$src" "$out_bin" >"$WORK_DIR/${base}.compile.stdout" 2>"$WORK_DIR/${base}.compile.stderr"
  rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    if ! grep -q "Parse error" "$WORK_DIR/${base}.compile.stdout" "$WORK_DIR/${base}.compile.stderr"; then
      echo "[stage1-conformance] FAIL(fail): $base unexpectedly compiled without parse error"
      exit 1
    fi
  fi

  fail_count=$((fail_count + 1))
done

echo "[stage1-conformance] PASS ($pass_count pass-cases, $fail_count fail-cases)"
