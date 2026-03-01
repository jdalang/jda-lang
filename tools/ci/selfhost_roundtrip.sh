#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGE0_BIN="$ROOT_DIR/bootstrap/stage0/jda0"
STAGE1_SRC="$ROOT_DIR/bootstrap/stage1/jda1.jda"

if [[ ! -x "$STAGE0_BIN" ]]; then
  echo "[selfhost-roundtrip] FAIL: missing Stage0 binary at $STAGE0_BIN"
  echo "[selfhost-roundtrip] run: make stage0"
  exit 1
fi

if [[ ! -f "$STAGE1_SRC" ]]; then
  echo "[selfhost-roundtrip] FAIL: missing Stage1 source at $STAGE1_SRC"
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

JDA1_A="$WORK_DIR/jda1_a"
JDA1_B="$WORK_DIR/jda1_b"
HELLO_A="$WORK_DIR/hello_a"
HELLO_B="$WORK_DIR/hello_b"

echo "[selfhost-roundtrip] stage0 -> stage1_a"
"$STAGE0_BIN" "$STAGE1_SRC" "$JDA1_A"
chmod +x "$JDA1_A"

echo "[selfhost-roundtrip] stage1_a -> stage1_b"
"$JDA1_A" "$STAGE1_SRC" "$JDA1_B"
chmod +x "$JDA1_B"

echo "[selfhost-roundtrip] compiling hello with stage1_a and stage1_b"
"$JDA1_A" "$ROOT_DIR/examples/hello.jda" "$HELLO_A"
"$JDA1_B" "$ROOT_DIR/examples/hello.jda" "$HELLO_B"
chmod +x "$HELLO_A" "$HELLO_B"

OUT_A="$("$HELLO_A")"
OUT_B="$("$HELLO_B")"

if [[ "$OUT_A" != "Hello Bare Metal" ]]; then
  echo "[selfhost-roundtrip] FAIL: stage1_a output mismatch: $OUT_A"
  exit 1
fi
if [[ "$OUT_B" != "Hello Bare Metal" ]]; then
  echo "[selfhost-roundtrip] FAIL: stage1_b output mismatch: $OUT_B"
  exit 1
fi

HASH_A="$(sha256sum "$JDA1_A" | awk '{print $1}')"
HASH_B="$(sha256sum "$JDA1_B" | awk '{print $1}')"

if [[ "$HASH_A" != "$HASH_B" ]]; then
  echo "[selfhost-roundtrip] FAIL: non-deterministic stage1 roundtrip"
  echo "  stage1_a: $HASH_A"
  echo "  stage1_b: $HASH_B"
  exit 1
fi

echo "[selfhost-roundtrip] verifying stage1_b conformance fixtures"
JDA1_BIN="$JDA1_B" bash "$ROOT_DIR/tools/ci/stage1_conformance.sh"

echo "[selfhost-roundtrip] PASS"
