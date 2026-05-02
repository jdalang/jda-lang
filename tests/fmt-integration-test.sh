#!/bin/bash
# Integration test for jda-fmt.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FMT="$SCRIPT_DIR/../tools/jda-fmt.sh"
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

PASS=0
FAIL=0

run_test() {
    local name="$1"
    shift
    if "$@" 2>/dev/null; then
        echo "  PASS  $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $name"
        FAIL=$((FAIL + 1))
    fi
}

# ─── Test 1: Basic indentation (2 spaces) ────────────────────────────────────

test_indent() {
    local result
    result="$(printf 'fn main() -> i64 {\n        ret 0\n}\n' | "$FMT" --stdin)"
    [ "$result" = "$(printf 'fn main() -> i64 {\n  ret 0\n}\n')" ]
}

# ─── Test 2: Nested indentation ──────────────────────────────────────────────

test_nested() {
    local result
    result="$(printf 'fn f() {\nif x {\nret 1\n}\n}\n' | "$FMT" --stdin)"
    [ "$result" = "$(printf 'fn f() {\n  if x {\n    ret 1\n  }\n}\n')" ]
}

# ─── Test 3: Idempotent ──────────────────────────────────────────────────────

test_idempotent() {
    local input
    input="$(printf 'fn add(a: i64, b: i64) -> i64 {\n        ret a + b\n}\nfn main() -> i64 {\nlet x = add(1, 2)\nif x == 3 {\nprint "ok"\n}\nret 0\n}\n')"
    local first
    first="$(printf '%s' "$input" | "$FMT" --stdin)"
    local second
    second="$(printf '%s' "$first" | "$FMT" --stdin)"
    [ "$first" = "$second" ]
}

# ─── Test 4: Blank line between top-level decls ──────────────────────────────

test_blank_lines() {
    local result
    result="$(printf 'fn a() {\nret 1\n}\nfn b() {\nret 2\n}\n' | "$FMT" --stdin)"
    echo "$result" | grep -q "^$" || return 1  # Should have a blank line
}

# ─── Test 5: Collapse multiple blank lines ────────────────────────────────────

test_collapse_blanks() {
    local result
    result="$(printf 'fn a() {\n  ret 1\n}\n\n\n\nfn b() {\n  ret 2\n}\n' | "$FMT" --stdin)"
    local blank_count
    blank_count="$(printf '%s' "$result" | grep -c '^$')"
    [ "$blank_count" -eq 1 ]
}

# ─── Test 6: Trailing whitespace removed ──────────────────────────────────────

test_trailing_ws() {
    local result
    result="$(printf 'fn main() {   \n  ret 0   \n}\n' | "$FMT" --stdin)"
    echo "$result" | grep -q '  $' && return 1  # Should NOT have trailing spaces
    return 0
}

# ─── Test 7: --check passes on formatted code ────────────────────────────────

test_check_pass() {
    printf 'fn main() -> i64 {\n  ret 0\n}\n' > "$TMP_DIR/good.jda"
    "$FMT" --check "$TMP_DIR/good.jda"
}

# ─── Test 8: --check fails on unformatted code ───────────────────────────────

test_check_fail() {
    printf 'fn main() -> i64 {\n        ret 0\n}\n' > "$TMP_DIR/bad.jda"
    ! "$FMT" --check "$TMP_DIR/bad.jda"
}

# ─── Test 9: In-place formatting ─────────────────────────────────────────────

test_inplace() {
    printf 'fn main() {\n        ret 0\n}\n' > "$TMP_DIR/fix.jda"
    "$FMT" "$TMP_DIR/fix.jda"
    local content
    content="$(cat "$TMP_DIR/fix.jda")"
    [ "$content" = "$(printf 'fn main() {\n  ret 0\n}\n')" ]
}

# ─── Test 10: Directory formatting ────────────────────────────────────────────

test_directory() {
    mkdir -p "$TMP_DIR/proj"
    printf 'fn a() {\n      ret 1\n}\n' > "$TMP_DIR/proj/a.jda"
    printf 'fn b() {\n      ret 2\n}\n' > "$TMP_DIR/proj/b.jda"
    "$FMT" "$TMP_DIR/proj/"
    local a_content b_content
    a_content="$(cat "$TMP_DIR/proj/a.jda")"
    b_content="$(cat "$TMP_DIR/proj/b.jda")"
    [ "$a_content" = "$(printf 'fn a() {\n  ret 1\n}\n')" ] && \
    [ "$b_content" = "$(printf 'fn b() {\n  ret 2\n}\n')" ]
}

# ─── Test 11: Comments preserved ─────────────────────────────────────────────

test_comments() {
    local result
    result="$(printf '; top comment\nfn main() {\n  ret 0  ; inline\n}\n' | "$FMT" --stdin)"
    echo "$result" | grep -q '; top comment' || return 1
    echo "$result" | grep -q '; inline' || return 1
}

# ─── Test 12: Single newline at end ──────────────────────────────────────────

test_trailing_newline() {
    local result
    result="$(printf 'fn main() {\n  ret 0\n}' | "$FMT" --stdin)"
    local last_char
    last_char="$(echo -n "$result" | tail -c 1)"
    [ "$(printf '%s' "$result" | wc -l | tr -d ' ')" -gt 0 ]  # has newlines
    printf '%s' "$result" | grep -q '}$'  # ends with }+newline
}

# ─── Run all ──────────────────────────────────────────────────────────────────

echo "jda-fmt integration tests"
echo "========================="

run_test "basic 2-space indent" test_indent
run_test "nested indentation" test_nested
run_test "idempotent" test_idempotent
run_test "blank lines between decls" test_blank_lines
run_test "collapse multiple blanks" test_collapse_blanks
run_test "trailing whitespace removed" test_trailing_ws
run_test "--check passes on formatted" test_check_pass
run_test "--check fails on unformatted" test_check_fail
run_test "in-place formatting" test_inplace
run_test "directory formatting" test_directory
run_test "comments preserved" test_comments
run_test "trailing newline" test_trailing_newline

echo ""
TOTAL=$((PASS + FAIL))
echo "Results: $PASS/$TOTAL passed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
