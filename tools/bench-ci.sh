#!/bin/bash
# Benchmark regression detection for CI
# Runs quick benchmarks and flags >5% regressions vs baseline
#
# Usage: tools/bench-ci.sh
# Expects jda1 at bootstrap/stage0/jda1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JDA="$ROOT/bootstrap/stage0/jda1"
TMP="$(mktemp -d)"
trap "rm -rf $TMP" EXIT

BASELINE_FILE="$ROOT/tools/bench-baseline.json"
THRESHOLD=5  # percent regression threshold

if [ ! -x "$JDA" ]; then
    echo "ERROR: jda1 not found at $JDA"
    exit 1
fi

echo "=== Benchmark Regression Check ==="
echo ""

# ─── Benchmark: self-compile time ────────────────────────────────────────────

echo "Benchmark: self-compile"
SRC="$ROOT/bootstrap/stage1/jda1.jda"
start=$(date +%s%N)
"$JDA" "$SRC" "$TMP/jda1_bench" 2>/dev/null
end=$(date +%s%N)
SELF_COMPILE_NS=$((end - start))
SELF_COMPILE_MS=$((SELF_COMPILE_NS / 1000000))
echo "  self-compile: ${SELF_COMPILE_MS}ms"

# ─── Benchmark: fib35 ────────────────────────────────────────────────────────

cat > "$TMP/fib35.jda" << 'EOF'
fn fib(n: i64) -> i64 {
    if n <= 1 { ret n }
    ret fib(n - 1) + fib(n - 2)
}
fn main() {
    let r = fib(35)
    print(r)
}
EOF

echo "Benchmark: fib35"
"$JDA" "$TMP/fib35.jda" "$TMP/fib35" 2>/dev/null
chmod +x "$TMP/fib35"
start=$(date +%s%N)
"$TMP/fib35" > /dev/null 2>&1 || true
end=$(date +%s%N)
FIB35_NS=$((end - start))
FIB35_MS=$((FIB35_NS / 1000000))
echo "  fib35: ${FIB35_MS}ms"

# ─── Benchmark: sum_loop (1M iterations) ─────────────────────────────────────

cat > "$TMP/sum_loop.jda" << 'EOF'
fn main() {
    let s = 0
    let i = 0
    loop i < 1000000 {
        s = s + i
        i = i + 1
    }
    print(s)
}
EOF

echo "Benchmark: sum_loop"
"$JDA" "$TMP/sum_loop.jda" "$TMP/sum_loop" 2>/dev/null
chmod +x "$TMP/sum_loop"
start=$(date +%s%N)
"$TMP/sum_loop" > /dev/null 2>&1 || true
end=$(date +%s%N)
SUM_LOOP_NS=$((end - start))
SUM_LOOP_MS=$((SUM_LOOP_NS / 1000000))
echo "  sum_loop: ${SUM_LOOP_MS}ms"

# ─── Benchmark: binary size ──────────────────────────────────────────────────

BIN_SIZE=$(wc -c < "$TMP/jda1_bench")
echo "Benchmark: binary size"
echo "  jda1 size: $BIN_SIZE bytes"

# ─── Write results ───────────────────────────────────────────────────────────

RESULTS="$TMP/results.json"
cat > "$RESULTS" << EOF
{
  "self_compile_ms": $SELF_COMPILE_MS,
  "fib35_ms": $FIB35_MS,
  "sum_loop_ms": $SUM_LOOP_MS,
  "binary_size": $BIN_SIZE
}
EOF

echo ""
echo "=== Results ==="
cat "$RESULTS"

# ─── Check for regression ────────────────────────────────────────────────────

if [ -f "$BASELINE_FILE" ]; then
    echo ""
    echo "=== Regression Check (threshold: ${THRESHOLD}%) ==="

    REGRESSED=0

    check_regression() {
        local name="$1"
        local current="$2"
        local baseline="$3"

        if [ "$baseline" -eq 0 ]; then
            echo "  $name: baseline=0, skip"
            return
        fi

        local diff=$((current - baseline))
        local pct=$((diff * 100 / baseline))

        if [ "$pct" -gt "$THRESHOLD" ]; then
            echo "  REGRESSION $name: ${baseline}ms -> ${current}ms (+${pct}%)"
            REGRESSED=1
        elif [ "$pct" -lt "-$THRESHOLD" ]; then
            echo "  IMPROVED $name: ${baseline}ms -> ${current}ms (${pct}%)"
        else
            echo "  OK $name: ${baseline}ms -> ${current}ms (${pct}%)"
        fi
    }

    # Parse baseline (simple grep-based, no jq dependency)
    B_SELF=$(grep "self_compile_ms" "$BASELINE_FILE" | grep -o '[0-9]*' | head -1)
    B_FIB=$(grep "fib35_ms" "$BASELINE_FILE" | grep -o '[0-9]*' | head -1)
    B_SUM=$(grep "sum_loop_ms" "$BASELINE_FILE" | grep -o '[0-9]*' | head -1)

    check_regression "self-compile" "$SELF_COMPILE_MS" "${B_SELF:-0}"
    check_regression "fib35" "$FIB35_MS" "${B_FIB:-0}"
    check_regression "sum_loop" "$SUM_LOOP_MS" "${B_SUM:-0}"

    if [ "$REGRESSED" -eq 1 ]; then
        echo ""
        echo "WARNING: Performance regression detected (>${THRESHOLD}%)"
        echo "This is informational — CI will not fail for benchmark regressions."
    fi
else
    echo ""
    echo "No baseline file at $BASELINE_FILE — skipping regression check."
    echo "To create baseline: cp $RESULTS $BASELINE_FILE"
fi

echo ""
echo "Benchmarks complete."
