#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGE0_DIR="$ROOT_DIR/bootstrap/stage0"
SUITE_DIR="$ROOT_DIR/tests/conformance/stage0"

PASS_DIR="$SUITE_DIR/pass"
FAIL_DIR="$SUITE_DIR/fail"

echo "[stage0-conformance] building Stage 0 compiler"
make -C "$STAGE0_DIR" all

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

pass_count=0
fail_count=0

echo "[stage0-conformance] running pass cases"
for src in "$PASS_DIR"/*.jda; do
  base="$(basename "$src" .jda)"
  out_bin="$WORK_DIR/${base}.out"
  run_out="$WORK_DIR/${base}.stdout"
  run_err="$WORK_DIR/${base}.stderr"
  expected="$PASS_DIR/${base}.expected"
  expected_exit_file="$PASS_DIR/${base}.exit"
  expected_exit=0
  if [[ -f "$expected_exit_file" ]]; then
    expected_exit="$(cat "$expected_exit_file")"
  fi

  "$STAGE0_DIR/jda0" "$src" "$out_bin" >"$WORK_DIR/${base}.compile.stdout" 2>"$WORK_DIR/${base}.compile.stderr"
  chmod +x "$out_bin"
  set +e
  "$out_bin" >"$run_out" 2>"$run_err"
  rc=$?
  set -e

  if [[ "$rc" != "$expected_exit" ]]; then
    echo "[stage0-conformance] FAIL(pass): $base exit code mismatch (expected $expected_exit, got $rc)"
    exit 1
  fi

  if ! cmp -s "$run_out" "$expected"; then
    echo "[stage0-conformance] FAIL(pass): $base output mismatch"
    echo "--- expected ---"
    cat "$expected"
    echo "--- actual ---"
    cat "$run_out"
    exit 1
  fi

  pass_count=$((pass_count + 1))
done

echo "[stage0-conformance] running fail cases"
for src in "$FAIL_DIR"/*.jda; do
  base="$(basename "$src" .jda)"
  out_bin="$WORK_DIR/${base}.out"
  stderr_expect="$FAIL_DIR/${base}.stderr_contains"

  if "$STAGE0_DIR/jda0" "$src" "$out_bin" >"$WORK_DIR/${base}.compile.stdout" 2>"$WORK_DIR/${base}.compile.stderr"; then
    echo "[stage0-conformance] FAIL(fail): $base compiled successfully but should fail"
    exit 1
  fi

  if ! grep -qF "$(cat "$stderr_expect")" "$WORK_DIR/${base}.compile.stderr"; then
    echo "[stage0-conformance] FAIL(fail): $base missing expected stderr marker"
    echo "--- expected substring ---"
    cat "$stderr_expect"
    echo "--- actual stderr ---"
    cat "$WORK_DIR/${base}.compile.stderr"
    exit 1
  fi

  fail_count=$((fail_count + 1))
done

echo "[stage0-conformance] PASS ($pass_count pass-cases, $fail_count fail-cases)"
