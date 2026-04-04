#!/bin/bash
# Integration test for stdlib expansion (io, os, math)
# Tests compilation and execution of stdlib functions via Docker

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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

compile_and_run() {
    local src="$1"
    local name="$2"
    # Concat stdlib + test, write to TMP_DIR, mount it into Docker
    cat "$ROOT/$src" "$TMP_DIR/${name}.jda" > "$TMP_DIR/${name}_full.jda"
    docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
        -v "$ROOT":/jda -v "$TMP_DIR":"$TMP_DIR" -w /jda/bootstrap/stage0 jda-build sh -c \
        "./jda1 $TMP_DIR/${name}_full.jda /tmp/${name} >/dev/null 2>&1 && /tmp/${name}" 2>/dev/null
}

# ─── math tests ──────────────────────────────────────────────────────────────

test_math_abs() {
    cat > "$TMP_DIR/math_abs.jda" << 'EOF'
fn main() {
    let a = math_abs(-42)
    let b = math_abs(7)
    if a == 42 {
        if b == 7 {
            print("abs ok")
        }
    }
}
EOF
    local out
    out="$(compile_and_run "stdlib/math.jda" "math_abs")"
    [ "$out" = "abs ok" ] || return 1
}

test_math_minmax() {
    cat > "$TMP_DIR/math_mm.jda" << 'EOF'
fn main() {
    let a = math_min(3, 7)
    let b = math_max(3, 7)
    if a == 3 {
        if b == 7 {
            print("minmax ok")
        }
    }
}
EOF
    local out
    out="$(compile_and_run "stdlib/math.jda" "math_mm")"
    [ "$out" = "minmax ok" ] || return 1
}

test_math_gcd() {
    cat > "$TMP_DIR/math_gcd.jda" << 'EOF'
fn main() {
    let g = math_gcd(12, 8)
    if g == 4 {
        print("gcd ok")
    }
}
EOF
    local out
    out="$(compile_and_run "stdlib/math.jda" "math_gcd")"
    [ "$out" = "gcd ok" ] || return 1
}

test_math_pow() {
    cat > "$TMP_DIR/math_pow.jda" << 'EOF'
fn main() {
    let r = math_pow(2, 10)
    if r == 1024 {
        print("pow ok")
    }
}
EOF
    local out
    out="$(compile_and_run "stdlib/math.jda" "math_pow")"
    [ "$out" = "pow ok" ] || return 1
}

test_math_isqrt() {
    cat > "$TMP_DIR/math_isqrt.jda" << 'EOF'
fn main() {
    let r = math_isqrt(100)
    if r == 10 {
        print("isqrt ok")
    }
}
EOF
    local out
    out="$(compile_and_run "stdlib/math.jda" "math_isqrt")"
    [ "$out" = "isqrt ok" ] || return 1
}

test_math_factorial() {
    cat > "$TMP_DIR/math_fact.jda" << 'EOF'
fn main() {
    let r = math_factorial(10)
    if r == 3628800 {
        print("fact ok")
    }
}
EOF
    local out
    out="$(compile_and_run "stdlib/math.jda" "math_fact")"
    [ "$out" = "fact ok" ] || return 1
}

test_math_fib() {
    cat > "$TMP_DIR/math_fib.jda" << 'EOF'
fn main() {
    let r = math_fib(20)
    if r == 6765 {
        print("fib ok")
    }
}
EOF
    local out
    out="$(compile_and_run "stdlib/math.jda" "math_fib")"
    [ "$out" = "fib ok" ] || return 1
}

test_math_prime() {
    cat > "$TMP_DIR/math_prime.jda" << 'EOF'
fn main() {
    let a = math_is_prime(97)
    let b = math_is_prime(100)
    if a == 1 {
        if b == 0 {
            print("prime ok")
        }
    }
}
EOF
    local out
    out="$(compile_and_run "stdlib/math.jda" "math_prime")"
    [ "$out" = "prime ok" ] || return 1
}

# ─── io tests ────────────────────────────────────────────────────────────────

test_io_write() {
    cat > "$TMP_DIR/io_write.jda" << 'EOF'
fn main() {
    io_write_stdout("io write ok", 11)
}
EOF
    local out
    out="$(compile_and_run "stdlib/io.jda" "io_write")"
    [ "$out" = "io write ok" ] || return 1
}

test_io_println() {
    cat > "$TMP_DIR/io_println.jda" << 'EOF'
fn main() {
    io_println("line1", 5)
    io_write_stdout("line2", 5)
}
EOF
    local out
    out="$(compile_and_run "stdlib/io.jda" "io_println")"
    [ "$out" = "$(printf 'line1\nline2')" ] || return 1
}

# ─── os tests ────────────────────────────────────────────────────────────────

test_os_getpid() {
    cat > "$TMP_DIR/os_getpid.jda" << 'EOF'
fn main() {
    let pid = os_getpid()
    if pid > 0 {
        print("pid ok")
    }
}
EOF
    local out
    out="$(compile_and_run "stdlib/os.jda" "os_getpid")"
    [ "$out" = "pid ok" ] || return 1
}

test_os_getcwd() {
    cat > "$TMP_DIR/os_getcwd.jda" << 'EOF'
fn main() {
    let buf = alloc_pages(1)
    let len = os_getcwd(buf, 4096)
    if len > 0 {
        print("cwd ok")
    }
}
EOF
    local out
    out="$(compile_and_run "stdlib/os.jda" "os_getcwd")"
    [ "$out" = "cwd ok" ] || return 1
}

# ─── Run all ──────────────────────────────────────────────────────────────────

echo "stdlib expansion integration tests"
echo "==================================="

run_test "math_abs" test_math_abs
run_test "math_minmax" test_math_minmax
run_test "math_gcd" test_math_gcd
run_test "math_pow" test_math_pow
run_test "math_isqrt" test_math_isqrt
run_test "math_factorial" test_math_factorial
run_test "math_fib" test_math_fib
run_test "math_prime" test_math_prime
run_test "io_write" test_io_write
run_test "io_println" test_io_println
run_test "os_getpid" test_os_getpid
run_test "os_getcwd" test_os_getcwd

echo ""
TOTAL=$((PASS + FAIL))
echo "Results: $PASS/$TOTAL passed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
