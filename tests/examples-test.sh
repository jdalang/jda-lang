#!/usr/bin/env bash
# Examples test — every shipped example must compile, run, and produce the
# output recorded beside it.
#
# This exists because four of the eight examples had stopped compiling without
# anyone noticing, including the two the README's ML claims rest on. Examples
# are the first thing a visitor runs, so they are held to the same standard as
# the conformance suite rather than being documentation that rots.
#
# Layout, per examples/<name>.jda:
#   <name>.expected   required — exact stdout+stderr of a successful run
#   <name>.include    optional — one path, passed as `build --include <path>`
#   <name>.sed        optional — sed -E script applied to actual output before
#                     comparison, for values that legitimately vary per run
#                     (timestamps, durations). Keep these narrow.
#
# --compile-only stops after the build. The native x86-64 runner has a
# pre-existing bug where programs allocating via alloc_pages produce no output
# (109 of 425 conformance tests fail there for the same reason, which is why
# that step is continue-on-error), and stdlib_demo allocates. Compilation is
# what actually regressed and is gated everywhere; execution is gated wherever
# the platform can actually execute.
set -uo pipefail

COMPILE_ONLY=0
[ "${1:-}" = "--compile-only" ] && COMPILE_ONLY=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JDA="${JDA1_BIN:-$ROOT/bootstrap/stage0/jda1}"
DIR="$ROOT/examples"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0

if [ ! -x "$JDA" ]; then echo "SKIP: jda1 not found at $JDA"; exit 0; fi

if [ "$COMPILE_ONLY" -eq 1 ]; then
    echo "=== Examples (compile only) ==="
else
    echo "=== Examples ==="
fi

for src in "$DIR"/*.jda; do
    name=$(basename "$src" .jda)
    expected="$DIR/$name.expected"

    if [ ! -f "$expected" ]; then
        echo "  FAIL  $name (no .expected file — add one, or move the example out of examples/)"
        FAIL=$((FAIL + 1)); continue
    fi

    inc=""
    if [ -f "$DIR/$name.include" ]; then
        inc="--include $(head -1 "$DIR/$name.include")"
    fi

    if ! compile_out=$(cd "$ROOT" && timeout 60 "$JDA" build $inc "$src" -o "$TMP/$name" 2>&1); then
        echo "  FAIL  $name (compile failed)"
        echo "          $(printf '%s' "$compile_out" | head -1)"
        FAIL=$((FAIL + 1)); continue
    fi

    if [ "$COMPILE_ONLY" -eq 1 ]; then
        echo "  PASS  $name (compiled)"; PASS=$((PASS + 1)); continue
    fi

    chmod +x "$TMP/$name" 2>/dev/null
    timeout 30 "$TMP/$name" > "$TMP/$name.out" 2>&1
    rc=$?
    if [ $rc -eq 124 ]; then
        echo "  FAIL  $name (timed out)"; FAIL=$((FAIL + 1)); continue
    elif [ $rc -ne 0 ]; then
        echo "  FAIL  $name (exited $rc)"
        echo "          $(head -1 "$TMP/$name.out")"
        FAIL=$((FAIL + 1)); continue
    fi

    if [ -f "$DIR/$name.sed" ]; then
        sed -E -f "$DIR/$name.sed" "$TMP/$name.out" > "$TMP/$name.norm"
    else
        cp "$TMP/$name.out" "$TMP/$name.norm"
    fi

    if diff -q "$expected" "$TMP/$name.norm" >/dev/null 2>&1; then
        echo "  PASS  $name"; PASS=$((PASS + 1))
    else
        echo "  FAIL  $name (output mismatch)"
        diff "$expected" "$TMP/$name.norm" | head -8 | sed 's/^/          /'
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== Results ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
if [ "$COMPILE_ONLY" -eq 1 ]; then
    echo "All examples compile."
else
    echo "All examples compile, run, and match their recorded output."
fi
