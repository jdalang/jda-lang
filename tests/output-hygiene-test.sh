#!/usr/bin/env bash
# Output hygiene test — guards the machine-readability contract of the compiler CLI:
#
#   1. A successful build writes NOTHING to stdout (and nothing to stderr).
#   2. Diagnostics go entirely to stderr, including line/column numbers.
#   3. Diagnostics carry a parseable file:line:col prefix.
#   4. --verbose restores progress output, on stdout.
#
# Regression guard for the fd-1/fd-2 split: eprint_i64 used to emit its digits
# via print_i64_dig (fd 1), so every line/col in every error message landed on
# stdout, interleaved out of order with the message text on stderr.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JDA="${JDA1_BIN:-$ROOT/bootstrap/stage0/jda1}"
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

PASS=0
FAIL=0

check() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS  $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $name"
        echo "          expected: $expected"
        echo "          actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

if [ ! -x "$JDA" ]; then
    echo "SKIP: jda1 not found at $JDA"
    exit 0
fi

cat > "$TMP_DIR/ok.jda" <<'JDA'
fn main() {
    print("hi")
}
JDA

# Error on line 4, column 9.
cat > "$TMP_DIR/bad.jda" <<'JDA'
fn main() {
    let x = 1
    if x > 0 
        print("hi")
    }
}
JDA

echo "=== Output Hygiene ==="

# 1. Successful build is silent on both streams.
out=$("$JDA" "$TMP_DIR/ok.jda" "$TMP_DIR/ok.bin" 2>/dev/null | wc -c | tr -d ' ')
check "clean build: 0 bytes on stdout" "0" "$out"

err=$("$JDA" "$TMP_DIR/ok.jda" "$TMP_DIR/ok.bin" 2>&1 >/dev/null | wc -c | tr -d ' ')
check "clean build: 0 bytes on stderr" "0" "$err"

# 2. The produced binary still works.
chmod +x "$TMP_DIR/ok.bin" 2>/dev/null
check "clean build: binary runs" "hi" "$("$TMP_DIR/ok.bin" 2>/dev/null)"

# 3. Failing build writes nothing to stdout.
out=$("$JDA" "$TMP_DIR/bad.jda" "$TMP_DIR/bad.bin" 2>/dev/null | wc -c | tr -d ' ')
check "failing build: 0 bytes on stdout" "0" "$out"

# 4. Diagnostic carries a parseable file:line:col prefix on stderr.
diag=$("$JDA" "$TMP_DIR/bad.jda" "$TMP_DIR/bad.bin" 2>&1 >/dev/null | head -1)
loc=$(echo "$diag" | sed -n 's/^.*bad\.jda:\([0-9]*\):\([0-9]*\): error: .*$/\1:\2/p')
check "diagnostic: file:line:col on stderr" "4:9" "$loc"

# 5. --verbose puts progress back on stdout.
vlines=$("$JDA" build --verbose "$TMP_DIR/ok.jda" -o "$TMP_DIR/ok2.bin" 2>/dev/null | wc -l | tr -d ' ')
if [ "$vlines" -gt 0 ]; then
    echo "  PASS  --verbose: progress restored on stdout ($vlines lines)"
    PASS=$((PASS + 1))
else
    echo "  FAIL  --verbose: expected progress output, got none"
    FAIL=$((FAIL + 1))
fi

# 6. Flags are order-independent.
"$JDA" build --verbose --safe "$TMP_DIR/ok.jda" -o "$TMP_DIR/ok3.bin" >/dev/null 2>&1
r1=$?
"$JDA" build --safe --verbose "$TMP_DIR/ok.jda" -o "$TMP_DIR/ok4.bin" >/dev/null 2>&1
r2=$?
check "flags accepted in either order" "0:0" "$r1:$r2"

echo ""
echo "=== Results ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
echo "All output hygiene tests passed."
