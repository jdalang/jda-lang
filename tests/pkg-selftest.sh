#!/usr/bin/env bash
# Compiles tools/pkg.jda and runs its built-in selftest.
#
# pkg.jda carries the only SHA-256 in the tree and the only semantic-version
# comparison, neither of which the conformance corpus covers. It also spent a
# long time not compiling at all, so this gate exists to keep it building.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JDA="${JDA1_BIN:-$ROOT/bootstrap/stage0/jda1}"
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

if [ ! -x "$JDA" ]; then echo "SKIP: jda1 not found at $JDA"; exit 0; fi

echo "=== pkg.jda selftest ==="

cat "$ROOT/stdlib/prelude.jda" "$ROOT/stdlib/fs.jda" > "$TMP_DIR/inc.jda"

if ! "$JDA" build --include "$TMP_DIR/inc.jda" "$ROOT/tools/pkg.jda" -o "$TMP_DIR/pkg" 2>"$TMP_DIR/err"; then
    echo "  FAIL  tools/pkg.jda does not compile"
    sed 's/^/          /' "$TMP_DIR/err"
    exit 1
fi
echo "  PASS  tools/pkg.jda compiles"

chmod +x "$TMP_DIR/pkg"
out=$("$TMP_DIR/pkg" selftest 2>&1); rc=$?
if [ $rc -ne 0 ]; then
    echo "  FAIL  selftest exited $rc"
    printf '%s\n' "$out" | sed 's/^/          /'
    exit 1
fi

if ! printf '%s' "$out" | grep -q "^selftest: all ok$"; then
    echo "  FAIL  selftest reported failures"
    printf '%s\n' "$out" | sed 's/^/          /'
    exit 1
fi
echo "  PASS  selftest: all assertions hold"

# The published SHA-256 test vector, checked explicitly so a silently wrong
# hash cannot pass by the selftest alone being green.
want="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
if printf '%s' "$out" | grep -q "sha256(abc) = $want"; then
    echo "  PASS  SHA-256(\"abc\") matches the published vector"
else
    echo "  FAIL  SHA-256(\"abc\") does not match"
    printf '%s\n' "$out" | grep sha256 | sed 's/^/          /'
    exit 1
fi

echo ""
echo "All pkg.jda selftests passed."
