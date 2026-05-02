#!/bin/bash
# Integration test for jda-macos.sh
# Tests macOS native compilation (x86-64, ARM64, universal)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS="$SCRIPT_DIR/../tools/jda-macos.sh"
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

# ─── Test 1: ARM64 assembly generation ──────────────────────────────────────

test_asm_arm64() {
    printf 'fn main() {\n  print "hello"\n  ret 0\n}\n' > "$TMP_DIR/basic.jda"
    local asm
    asm="$(python3 "$MACOS" --asm --arch arm64 "$TMP_DIR/basic.jda")"
    echo "$asm" | grep -q "_main:" || return 1
    echo "$asm" | grep -q "stp x29, x30" || return 1
    echo "$asm" | grep -q "svc #0x80" || return 1
    echo "$asm" | grep -q "__TEXT,__text" || return 1
}

# ─── Test 2: x86-64 assembly generation ─────────────────────────────────────

test_asm_x86() {
    printf 'fn main() {\n  print "hello"\n  ret 0\n}\n' > "$TMP_DIR/basic.jda"
    local asm
    asm="$(python3 "$MACOS" --asm --arch x86_64 "$TMP_DIR/basic.jda")"
    echo "$asm" | grep -q "_main:" || return 1
    echo "$asm" | grep -q "pushq %rbp" || return 1
    echo "$asm" | grep -q "syscall" || return 1
    echo "$asm" | grep -q "0x2000004" || return 1
}

# ─── Test 3: ARM64 binary compilation ───────────────────────────────────────

test_build_arm64() {
    printf 'fn main() {\n  print "arm64"\n  ret 0\n}\n' > "$TMP_DIR/arm.jda"
    python3 "$MACOS" --arch arm64 -o "$TMP_DIR/arm" "$TMP_DIR/arm.jda" > /dev/null 2>&1 || return 1
    file "$TMP_DIR/arm" | grep -q "arm64" || return 1
}

# ─── Test 4: x86-64 binary compilation ──────────────────────────────────────

test_build_x86() {
    printf 'fn main() {\n  print "x86"\n  ret 0\n}\n' > "$TMP_DIR/x86.jda"
    python3 "$MACOS" --arch x86_64 -o "$TMP_DIR/x86" "$TMP_DIR/x86.jda" > /dev/null 2>&1 || return 1
    file "$TMP_DIR/x86" | grep -q "x86_64" || return 1
}

# ─── Test 5: ARM64 binary execution ─────────────────────────────────────────

test_run_arm64() {
    printf 'fn main() {\n  print "hello arm64"\n  ret 0\n}\n' > "$TMP_DIR/run_arm.jda"
    python3 "$MACOS" --arch arm64 -o "$TMP_DIR/run_arm" "$TMP_DIR/run_arm.jda" > /dev/null 2>&1 || return 1
    local out
    out="$("$TMP_DIR/run_arm" 2>&1)"
    [ "$out" = "hello arm64" ] || return 1
}

# ─── Test 6: x86-64 binary execution ────────────────────────────────────────

test_run_x86() {
    printf 'fn main() {\n  print "hello x86"\n  ret 0\n}\n' > "$TMP_DIR/run_x86.jda"
    python3 "$MACOS" --arch x86_64 -o "$TMP_DIR/run_x86" "$TMP_DIR/run_x86.jda" > /dev/null 2>&1 || return 1
    local out
    out="$("$TMP_DIR/run_x86" 2>&1)"
    [ "$out" = "hello x86" ] || return 1
}

# ─── Test 7: Universal binary ───────────────────────────────────────────────

test_universal() {
    printf 'fn main() {\n  print "universal"\n  ret 0\n}\n' > "$TMP_DIR/uni.jda"
    python3 "$MACOS" --universal -o "$TMP_DIR/uni" "$TMP_DIR/uni.jda" > /dev/null 2>&1 || return 1
    file "$TMP_DIR/uni" | grep -q "universal binary" || return 1
    file "$TMP_DIR/uni" | grep -q "x86_64" || return 1
    file "$TMP_DIR/uni" | grep -q "arm64" || return 1
}

# ─── Test 8: Function calls ─────────────────────────────────────────────────

test_fn_calls() {
    printf 'fn add(a: i64, b: i64) -> i64 {\n  ret a + b\n}\nfn main() {\n  let x = add(3, 4)\n  if x == 7 {\n    print "call ok"\n  }\n  ret 0\n}\n' > "$TMP_DIR/call.jda"
    python3 "$MACOS" -o "$TMP_DIR/call" "$TMP_DIR/call.jda" > /dev/null 2>&1 || return 1
    local out
    out="$("$TMP_DIR/call" 2>&1)"
    [ "$out" = "call ok" ] || return 1
}

# ─── Test 9: Arithmetic operations ──────────────────────────────────────────

test_arithmetic() {
    printf 'fn main() {\n  let a = 3 + 4\n  let b = 10 - 3\n  let c = 5 * 6\n  if a == 7 {\n    if b == 7 {\n      if c == 30 {\n        print "math ok"\n      }\n    }\n  }\n  ret 0\n}\n' > "$TMP_DIR/math.jda"
    python3 "$MACOS" -o "$TMP_DIR/math" "$TMP_DIR/math.jda" > /dev/null 2>&1 || return 1
    local out
    out="$("$TMP_DIR/math" 2>&1)"
    [ "$out" = "math ok" ] || return 1
}

# ─── Test 10: Recursive function ────────────────────────────────────────────

test_recursive() {
    printf 'fn fib(n: i64) -> i64 {\n  if n <= 1 {\n    ret n\n  }\n  let a = fib(n - 1)\n  let b = fib(n - 2)\n  ret a + b\n}\nfn main() {\n  let r = fib(10)\n  if r == 55 {\n    print "fib ok"\n  }\n  ret 0\n}\n' > "$TMP_DIR/fib.jda"
    python3 "$MACOS" -o "$TMP_DIR/fib" "$TMP_DIR/fib.jda" > /dev/null 2>&1 || return 1
    local out
    out="$("$TMP_DIR/fib" 2>&1)"
    [ "$out" = "fib ok" ] || return 1
}

# ─── Test 11: Code signing ──────────────────────────────────────────────────

test_codesign() {
    printf 'fn main() {\n  ret 0\n}\n' > "$TMP_DIR/sign.jda"
    python3 "$MACOS" -o "$TMP_DIR/sign" "$TMP_DIR/sign.jda" > /dev/null 2>&1 || return 1
    codesign -vv "$TMP_DIR/sign" > /dev/null 2>&1 || return 1
}

# ─── Test 12: macOS syscall ABI ──────────────────────────────────────────────

test_syscall_abi() {
    # Verify macOS x86-64 uses 0x2000000 prefix
    printf 'fn main() {\n  syscall(1, 0, 0, 0)\n  ret 0\n}\n' > "$TMP_DIR/sys.jda"
    local asm
    asm="$(python3 "$MACOS" --asm --arch x86_64 "$TMP_DIR/sys.jda")"
    echo "$asm" | grep -q "0x2000000" || return 1
    # Verify ARM64 uses x16 + svc #0x80
    asm="$(python3 "$MACOS" --asm --arch arm64 "$TMP_DIR/sys.jda")"
    echo "$asm" | grep -q "x16" || return 1
    echo "$asm" | grep -q "svc #0x80" || return 1
}

# ─── Run all ──────────────────────────────────────────────────────────────────

echo "jda-macos integration tests"
echo "==========================="

run_test "ARM64 assembly" test_asm_arm64
run_test "x86-64 assembly" test_asm_x86
run_test "ARM64 binary" test_build_arm64
run_test "x86-64 binary" test_build_x86
run_test "ARM64 execution" test_run_arm64
run_test "x86-64 execution" test_run_x86
run_test "universal binary" test_universal
run_test "function calls" test_fn_calls
run_test "arithmetic" test_arithmetic
run_test "recursive function" test_recursive
run_test "code signing" test_codesign
run_test "macOS syscall ABI" test_syscall_abi

echo ""
TOTAL=$((PASS + FAIL))
echo "Results: $PASS/$TOTAL passed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
