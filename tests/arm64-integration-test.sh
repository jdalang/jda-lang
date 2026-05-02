#!/bin/bash
# Integration test for jda-arm64.sh
# Tests ARM64 code generation (assembly output)
# Binary execution requires aarch64 tools or Docker arm64

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARM64="$SCRIPT_DIR/../tools/jda-arm64.sh"
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

# ─── Test 1: Basic assembly generation ────────────────────────────────────────

test_asm_basic() {
    printf 'fn main() -> i64 {\n  ret 0\n}\n' > "$TMP_DIR/basic.jda"
    local asm
    asm="$("$ARM64" --asm "$TMP_DIR/basic.jda")"
    echo "$asm" | grep -q "_start:" || return 1
    echo "$asm" | grep -q "main:" || return 1
    echo "$asm" | grep -q "svc #0" || return 1
    echo "$asm" | grep -q "stp x29, x30" || return 1
}

# ─── Test 2: AAPCS64 prologue/epilogue ────────────────────────────────────────

test_abi_prologue() {
    printf 'fn main() -> i64 {\n  ret 42\n}\n' > "$TMP_DIR/abi.jda"
    local asm
    asm="$("$ARM64" --asm "$TMP_DIR/abi.jda")"
    echo "$asm" | grep -q "stp x29, x30" || return 1   # save FP+LR
    echo "$asm" | grep -q "mov x29, sp" || return 1     # set FP
    echo "$asm" | grep -q "ldp x29, x30" || return 1   # restore FP+LR
    echo "$asm" | grep -q "ret" || return 1
}

# ─── Test 3: Function calls with args ────────────────────────────────────────

test_fn_calls() {
    printf 'fn add(a: i64, b: i64) -> i64 {\n  ret a + b\n}\nfn main() -> i64 {\n  let x = add(3, 4)\n  ret 0\n}\n' > "$TMP_DIR/call.jda"
    local asm
    asm="$("$ARM64" --asm "$TMP_DIR/call.jda")"
    echo "$asm" | grep -q "bl add" || return 1
    echo "$asm" | grep -q "add:" || return 1
}

# ─── Test 4: Arithmetic operations ───────────────────────────────────────────

test_arithmetic() {
    printf 'fn main() -> i64 {\n  let x = 3 + 4\n  let y = 10 - 3\n  let z = 5 * 6\n  ret 0\n}\n' > "$TMP_DIR/arith.jda"
    local asm
    asm="$("$ARM64" --asm "$TMP_DIR/arith.jda")"
    echo "$asm" | grep -q "add x0" || return 1
    echo "$asm" | grep -q "sub x0" || return 1
    echo "$asm" | grep -q "mul x0" || return 1
}

# ─── Test 5: Comparisons ─────────────────────────────────────────────────────

test_comparisons() {
    printf 'fn main() -> i64 {\n  let a = 1 == 1\n  let b = 1 != 2\n  let c = 3 < 5\n  ret 0\n}\n' > "$TMP_DIR/cmp.jda"
    local asm
    asm="$("$ARM64" --asm "$TMP_DIR/cmp.jda")"
    echo "$asm" | grep -q "cmp x0" || return 1
    echo "$asm" | grep -q "cset x0" || return 1
}

# ─── Test 6: Conditionals ────────────────────────────────────────────────────

test_conditionals() {
    printf 'fn main() -> i64 {\n  if 1 == 1 {\n    ret 0\n  }\n  ret 1\n}\n' > "$TMP_DIR/cond.jda"
    local asm
    asm="$("$ARM64" --asm "$TMP_DIR/cond.jda")"
    echo "$asm" | grep -q "cbz" || return 1
}

# ─── Test 7: String output ───────────────────────────────────────────────────

test_strings() {
    printf 'fn main() -> i64 {\n  print "hello"\n  ret 0\n}\n' > "$TMP_DIR/str.jda"
    local asm
    asm="$("$ARM64" --asm "$TMP_DIR/str.jda")"
    echo "$asm" | grep -q ".rodata" || return 1
    echo "$asm" | grep -q "mov x8, #64" || return 1    # write syscall
    echo "$asm" | grep -q "adrp" || return 1            # PC-relative addr
}

# ─── Test 8: Syscall generation ──────────────────────────────────────────────

test_syscall() {
    printf 'fn main() -> i64 {\n  syscall(93, 0, 0, 0)\n  ret 0\n}\n' > "$TMP_DIR/sys.jda"
    local asm
    asm="$("$ARM64" --asm "$TMP_DIR/sys.jda")"
    echo "$asm" | grep -q "mov x8" || return 1
    echo "$asm" | grep -q "svc #0" || return 1
}

# ─── Test 9: ELF header (cross-assemble) ─────────────────────────────────────

test_elf_cross() {
    printf 'fn main() -> i64 {\n  ret 0\n}\n' > "$TMP_DIR/elf.jda"
    "$ARM64" --asm "$TMP_DIR/elf.jda" > "$TMP_DIR/elf.s"
    # Try cross-assemble with Docker
    docker run --rm --platform linux/amd64 \
        -v "$TMP_DIR:$TMP_DIR" -w "$TMP_DIR" \
        jda-build sh -c "apt-get update -qq >/dev/null 2>&1 && apt-get install -qq -y binutils-aarch64-linux-gnu >/dev/null 2>&1 && aarch64-linux-gnu-as -o $TMP_DIR/elf.o $TMP_DIR/elf.s && aarch64-linux-gnu-ld -o $TMP_DIR/elf $TMP_DIR/elf.o -static" 2>/dev/null || return 1
    file "$TMP_DIR/elf" | grep -q "ARM aarch64" || return 1
}

# ─── Test 10: Multiple functions ──────────────────────────────────────────────

test_multi_fn() {
    printf 'fn square(x: i64) -> i64 {\n  ret x * x\n}\nfn double(x: i64) -> i64 {\n  ret x + x\n}\nfn main() -> i64 {\n  let a = square(5)\n  let b = double(3)\n  ret 0\n}\n' > "$TMP_DIR/multi.jda"
    local asm
    asm="$("$ARM64" --asm "$TMP_DIR/multi.jda")"
    echo "$asm" | grep -q "square:" || return 1
    echo "$asm" | grep -q "double:" || return 1
    echo "$asm" | grep -q "bl square" || return 1
    echo "$asm" | grep -q "bl double" || return 1
}

# ─── Test 11: Recursive function ─────────────────────────────────────────────

test_recursive() {
    printf 'fn fib(n: i64) -> i64 {\n  if n <= 1 {\n    ret n\n  }\n  ret fib(n - 1) + fib(n - 2)\n}\nfn main() -> i64 {\n  let r = fib(10)\n  ret 0\n}\n' > "$TMP_DIR/rec.jda"
    local asm
    asm="$("$ARM64" --asm "$TMP_DIR/rec.jda")"
    echo "$asm" | grep -q "bl fib" || return 1
    echo "$asm" | grep -q "fib:" || return 1
}

# ─── Test 12: Exit code in x0 ────────────────────────────────────────────────

test_exit_code() {
    printf 'fn main() -> i64 {\n  ret 0\n}\n' > "$TMP_DIR/exit.jda"
    local asm
    asm="$("$ARM64" --asm "$TMP_DIR/exit.jda")"
    # _start should pass x0 (return from main) to exit syscall
    echo "$asm" | grep -q "mov x8, #93" || return 1
}

# ─── Run all ──────────────────────────────────────────────────────────────────

echo "jda-arm64 integration tests"
echo "==========================="

run_test "basic assembly" test_asm_basic
run_test "AAPCS64 prologue/epilogue" test_abi_prologue
run_test "function calls" test_fn_calls
run_test "arithmetic ops" test_arithmetic
run_test "comparisons" test_comparisons
run_test "conditionals" test_conditionals
run_test "string output" test_strings
run_test "syscall generation" test_syscall
run_test "ELF cross-assemble" test_elf_cross
run_test "multiple functions" test_multi_fn
run_test "recursive function" test_recursive
run_test "exit code" test_exit_code

echo ""
TOTAL=$((PASS + FAIL))
echo "Results: $PASS/$TOTAL passed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
