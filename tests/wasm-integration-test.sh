#!/bin/bash
# Integration test for jda-wasm.sh
# Tests WebAssembly compilation (WASI + browser targets)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WASM="$SCRIPT_DIR/../tools/jda-wasm.sh"
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

run_wasi() {
    local wasm="$1"
    node --no-warnings -e "
const fs = require('fs');
const { WASI } = require('wasi');
const wasi = new WASI({ version: 'preview1' });
const wasm = fs.readFileSync('$wasm');
WebAssembly.compile(wasm).then(m =>
  WebAssembly.instantiate(m, wasi.getImportObject())
).then(i => wasi.start(i));
" 2>&1
}

# ─── Test 1: WAT generation (WASI) ──────────────────────────────────────────

test_wat_wasi() {
    printf 'fn main() {\n  print "hello"\n  ret 0\n}\n' > "$TMP_DIR/basic.jda"
    local wat
    wat="$(python3 "$WASM" --wat "$TMP_DIR/basic.jda")"
    echo "$wat" | grep -q "(module" || return 1
    echo "$wat" | grep -q "fd_write" || return 1
    echo "$wat" | grep -q "_start" || return 1
    echo "$wat" | grep -q "i64.const 0" || return 1
}

# ─── Test 2: WAT generation (browser) ───────────────────────────────────────

test_wat_browser() {
    printf 'fn main() {\n  print "hello"\n  ret 0\n}\n' > "$TMP_DIR/browser.jda"
    local wat
    wat="$(python3 "$WASM" --wat --target browser "$TMP_DIR/browser.jda")"
    echo "$wat" | grep -q "print_str" || return 1
    echo "$wat" | grep -q '"memory"' || return 1
}

# ─── Test 3: WASM binary compilation ────────────────────────────────────────

test_wasm_compile() {
    printf 'fn main() {\n  print "wasm"\n  ret 0\n}\n' > "$TMP_DIR/comp.jda"
    python3 "$WASM" -o "$TMP_DIR/comp.wasm" "$TMP_DIR/comp.jda" > /dev/null 2>&1 || return 1
    [ -f "$TMP_DIR/comp.wasm" ] || return 1
    # Check WASM magic number
    local magic
    magic="$(xxd -l 4 "$TMP_DIR/comp.wasm" | head -1)"
    echo "$magic" | grep -q "0061 736d" || return 1
}

# ─── Test 4: WASM execution (hello world) ───────────────────────────────────

test_wasm_run_hello() {
    printf 'fn main() {\n  print "hello wasm"\n  ret 0\n}\n' > "$TMP_DIR/hello.jda"
    python3 "$WASM" -o "$TMP_DIR/hello.wasm" "$TMP_DIR/hello.jda" > /dev/null 2>&1 || return 1
    local out
    out="$(run_wasi "$TMP_DIR/hello.wasm")"
    [ "$out" = "hello wasm" ] || return 1
}

# ─── Test 5: Function calls ─────────────────────────────────────────────────

test_fn_calls() {
    printf 'fn add(a: i64, b: i64) -> i64 {\n  ret a + b\n}\nfn main() {\n  let x = add(3, 4)\n  if x == 7 {\n    print "call ok"\n  }\n  ret 0\n}\n' > "$TMP_DIR/call.jda"
    python3 "$WASM" -o "$TMP_DIR/call.wasm" "$TMP_DIR/call.jda" > /dev/null 2>&1 || return 1
    local out
    out="$(run_wasi "$TMP_DIR/call.wasm")"
    [ "$out" = "call ok" ] || return 1
}

# ─── Test 6: Arithmetic ─────────────────────────────────────────────────────

test_arithmetic() {
    printf 'fn main() {\n  let a = 3 + 4\n  let b = 10 - 3\n  let c = 5 * 6\n  if a == 7 {\n    if b == 7 {\n      if c == 30 {\n        print "math ok"\n      }\n    }\n  }\n  ret 0\n}\n' > "$TMP_DIR/math.jda"
    python3 "$WASM" -o "$TMP_DIR/math.wasm" "$TMP_DIR/math.jda" > /dev/null 2>&1 || return 1
    local out
    out="$(run_wasi "$TMP_DIR/math.wasm")"
    [ "$out" = "math ok" ] || return 1
}

# ─── Test 7: Comparisons ────────────────────────────────────────────────────

test_comparisons() {
    printf 'fn main() {\n  let a = 5 > 3\n  let b = 2 < 8\n  let c = 5 != 3\n  if a == 1 {\n    if b == 1 {\n      if c == 1 {\n        print "cmp ok"\n      }\n    }\n  }\n  ret 0\n}\n' > "$TMP_DIR/cmp.jda"
    python3 "$WASM" -o "$TMP_DIR/cmp.wasm" "$TMP_DIR/cmp.jda" > /dev/null 2>&1 || return 1
    local out
    out="$(run_wasi "$TMP_DIR/cmp.wasm")"
    [ "$out" = "cmp ok" ] || return 1
}

# ─── Test 8: Recursive function ─────────────────────────────────────────────

test_recursive() {
    printf 'fn fib(n: i64) -> i64 {\n  if n <= 1 {\n    ret n\n  }\n  let a = fib(n - 1)\n  let b = fib(n - 2)\n  ret a + b\n}\nfn main() {\n  let r = fib(10)\n  if r == 55 {\n    print "fib ok"\n  }\n  ret 0\n}\n' > "$TMP_DIR/fib.jda"
    python3 "$WASM" -o "$TMP_DIR/fib.wasm" "$TMP_DIR/fib.jda" > /dev/null 2>&1 || return 1
    local out
    out="$(run_wasi "$TMP_DIR/fib.wasm")"
    [ "$out" = "fib ok" ] || return 1
}

# ─── Test 9: Loop ───────────────────────────────────────────────────────────

test_loop() {
    printf 'fn main() {\n  let i = 0\n  let s = 0\n  loop i < 10 {\n    s = s + i\n    i = i + 1\n  }\n  if s == 45 {\n    print "loop ok"\n  }\n  ret 0\n}\n' > "$TMP_DIR/loop.jda"
    python3 "$WASM" -o "$TMP_DIR/loop.wasm" "$TMP_DIR/loop.jda" > /dev/null 2>&1 || return 1
    local out
    out="$(run_wasi "$TMP_DIR/loop.wasm")"
    [ "$out" = "loop ok" ] || return 1
}

# ─── Test 10: Multiple functions ─────────────────────────────────────────────

test_multi_fn() {
    printf 'fn square(x: i64) -> i64 {\n  ret x * x\n}\nfn double(x: i64) -> i64 {\n  ret x + x\n}\nfn main() {\n  let a = square(5)\n  let b = double(3)\n  if a == 25 {\n    if b == 6 {\n      print "multi ok"\n    }\n  }\n  ret 0\n}\n' > "$TMP_DIR/multi.jda"
    python3 "$WASM" -o "$TMP_DIR/multi.wasm" "$TMP_DIR/multi.jda" > /dev/null 2>&1 || return 1
    local out
    out="$(run_wasi "$TMP_DIR/multi.wasm")"
    [ "$out" = "multi ok" ] || return 1
}

# ─── Test 11: HTML playground ────────────────────────────────────────────────

test_html_playground() {
    printf 'fn main() {\n  print "play"\n  ret 0\n}\n' > "$TMP_DIR/play.jda"
    python3 "$WASM" --html -o "$TMP_DIR/play.html" "$TMP_DIR/play.jda" > /dev/null 2>&1 || return 1
    [ -f "$TMP_DIR/play.html" ] || return 1
    grep -q "Jda Playground" "$TMP_DIR/play.html" || return 1
    grep -q "WASM_BASE64" "$TMP_DIR/play.html" || return 1
    grep -q "WebAssembly" "$TMP_DIR/play.html" || return 1
}

# ─── Test 12: Linear memory (data segments) ─────────────────────────────────

test_memory() {
    printf 'fn main() {\n  print "abc"\n  print "def"\n  ret 0\n}\n' > "$TMP_DIR/mem.jda"
    local wat
    wat="$(python3 "$WASM" --wat "$TMP_DIR/mem.jda")"
    # Should have two data segments
    local count
    count="$(echo "$wat" | grep -c "(data")"
    [ "$count" -ge 2 ] || return 1
    # Should use linear memory
    echo "$wat" | grep -q "(memory" || return 1
}

# ─── Run all ──────────────────────────────────────────────────────────────────

echo "jda-wasm integration tests"
echo "=========================="

run_test "WAT generation (WASI)" test_wat_wasi
run_test "WAT generation (browser)" test_wat_browser
run_test "WASM binary compilation" test_wasm_compile
run_test "WASM hello world" test_wasm_run_hello
run_test "function calls" test_fn_calls
run_test "arithmetic" test_arithmetic
run_test "comparisons" test_comparisons
run_test "recursive function" test_recursive
run_test "loop" test_loop
run_test "multiple functions" test_multi_fn
run_test "HTML playground" test_html_playground
run_test "linear memory" test_memory

echo ""
TOTAL=$((PASS + FAIL))
echo "Results: $PASS/$TOTAL passed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
