#!/usr/bin/env bash
# Rejected-syntax test — every case here is syntax that appears in Jda's own
# documentation or reads naturally to someone (or some model) writing Jda, and
# that the compiler ACCEPTED while producing wrong code: an empty loop body, a
# function returning 0, a vanished interpolation, a segfault at runtime.
#
# Each case must now fail to compile with a specific diagnostic. A case that
# starts compiling again is a regression: either the feature was implemented
# (move it to tests/conformance/stage1/pass/) or a silent miscompile came back.
#
# Layout: tests/rejected/<name>.jda + tests/rejected/<name>.expected-error,
# where the .expected-error file holds a substring of the required message.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JDA="${JDA1_BIN:-$ROOT/bootstrap/stage0/jda1}"
DIR="$ROOT/tests/rejected"
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

PASS=0
FAIL=0

if [ ! -x "$JDA" ]; then
    echo "SKIP: jda1 not found at $JDA"
    exit 0
fi

echo "=== Rejected Syntax ==="

for src in "$DIR"/*.jda; do
    name=$(basename "$src" .jda)
    want_file="$DIR/$name.expected-error"
    if [ ! -f "$want_file" ]; then
        echo "  FAIL  $name (no .expected-error file)"
        FAIL=$((FAIL + 1))
        continue
    fi
    want=$(cat "$want_file")

    err=$(timeout 30 "$JDA" "$src" "$TMP_DIR/$name.bin" 2>&1 >/dev/null)
    rc=$?

    if [ $rc -eq 124 ]; then
        echo "  FAIL  $name (compiler hung)"
        FAIL=$((FAIL + 1))
    elif [ -z "$err" ]; then
        echo "  FAIL  $name (compiled silently; expected: $want)"
        FAIL=$((FAIL + 1))
    elif ! printf '%s' "$err" | grep -qF "$want"; then
        echo "  FAIL  $name (wrong diagnostic)"
        echo "          expected substring: $want"
        echo "          actual:             $(printf '%s' "$err" | head -1)"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS  $name"
        PASS=$((PASS + 1))
    fi
done

echo ""
echo "=== Results ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
echo "All rejected-syntax tests passed."
