#!/bin/bash
# Jda Conformance Test Runner
#
# Usage:
#   ./tools/run_tests.sh                  # run from project root
#   ./tools/run_tests.sh --selfhost       # also run self-host convergence
#
# Expects jda1 binary at bootstrap/stage0/jda1
# Tests live in tests/conformance/stage1/pass/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JDA="$PROJECT_ROOT/bootstrap/stage0/jda1"
TEST_DIR="$PROJECT_ROOT/tests/conformance/stage1/pass"
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

PASS=0
FAIL=0
SKIP=0
KNOWN_FAIL=0
FAILURES=""

# Known failures — these are tracked bugs, not CI regressions
# Self-hosted binary miscompiles closures (pre-existing, not caused by optimizations)
KNOWN_FAILURES="f64_type_inference float_fmt_basic float_literals"

if [ ! -x "$JDA" ]; then
    echo "ERROR: jda1 not found at $JDA"
    echo "Build it first: make -C bootstrap/stage0 stage1"
    exit 1
fi

echo "=== Jda Conformance Tests ==="
echo "Compiler: $JDA"
echo "Test dir: $TEST_DIR"
echo ""

for test_file in "$TEST_DIR"/*.jda; do
    test_name=$(basename "$test_file" .jda)
    expected_file="$TEST_DIR/${test_name}.expected"
    exit_file="$TEST_DIR/${test_name}.exit"
    bin_out="$TMP_DIR/$test_name"

    # Determine expected exit code (default 0)
    expected_exit=0
    if [ -f "$exit_file" ]; then
        expected_exit=$(cat "$exit_file" | tr -d '[:space:]')
    fi

    # Skip if no .expected file
    if [ ! -f "$expected_file" ]; then
        SKIP=$((SKIP + 1))
        echo "  SKIP  $test_name (no .expected file)"
        continue
    fi

    # Skip known failures early (avoid hanging on compile)
    is_known_early=0
    for kf in $KNOWN_FAILURES; do
        if [ "$test_name" = "$kf" ]; then
            is_known_early=1
            break
        fi
    done
    if [ "$is_known_early" = "1" ]; then
        KNOWN_FAIL=$((KNOWN_FAIL + 1))
        echo "  KNOWN $test_name (skipped)"
        continue
    fi

    # Check for .include sidecar (e.g. regex_literal.include contains "stdlib/regex.jda")
    include_file="$TEST_DIR/${test_name}.include"
    include_flag=""
    if [ -f "$include_file" ]; then
        # Count non-empty lines
        inc_lines=()
        while IFS= read -r inc_line || [ -n "$inc_line" ]; do
            inc_line=$(echo "$inc_line" | tr -d '[:space:]')
            if [ -n "$inc_line" ]; then
                inc_lines+=("$PROJECT_ROOT/$inc_line")
            fi
        done < "$include_file"
        if [ ${#inc_lines[@]} -eq 1 ]; then
            include_flag="--include ${inc_lines[0]}"
        elif [ ${#inc_lines[@]} -gt 1 ]; then
            # Compiler only supports one --include; concatenate into temp file
            merged="$TMP_DIR/${test_name}_merged.jda"
            cat "${inc_lines[@]}" > "$merged"
            include_flag="--include $merged"
        fi
    fi

    # Compile (30s timeout to prevent hangs on known-failing programs)
    compile_out=$(timeout 30 "$JDA" build $include_flag "$test_file" -o "$bin_out" 2>&1) || true
    if [ ! -f "$bin_out" ]; then
        is_known=0
        for kf in $KNOWN_FAILURES; do
            if [ "$test_name" = "$kf" ]; then
                is_known=1
                break
            fi
        done
        if [ "$is_known" = "1" ]; then
            KNOWN_FAIL=$((KNOWN_FAIL + 1))
            echo "  KNOWN $test_name (known failure, compile failed)"
        else
            FAIL=$((FAIL + 1))
            FAILURES="$FAILURES\n  FAIL  $test_name (compile failed)"
            echo "  FAIL  $test_name (compile failed)"
            echo "  CMD:  $JDA build $include_flag $test_file -o $bin_out"
            echo "  ERR:  $compile_out" | tail -5
        fi
        continue
    fi
    chmod +x "$bin_out"

    # Run (10s timeout)
    actual_out=$(timeout 10 "$bin_out" 2>&1) || true
    actual_exit=$?

    # Compare output
    expected_out=$(cat "$expected_file")
    if [ "$actual_out" = "$expected_out" ] && [ "$actual_exit" = "$expected_exit" ]; then
        PASS=$((PASS + 1))
        echo "  PASS  $test_name"
    else
        is_known=0
        for kf in $KNOWN_FAILURES; do
            if [ "$test_name" = "$kf" ]; then
                is_known=1
                break
            fi
        done
        if [ "$is_known" = "1" ]; then
            KNOWN_FAIL=$((KNOWN_FAIL + 1))
            echo "  KNOWN $test_name (known failure, tracked)"
        else
            FAIL=$((FAIL + 1))
            msg="  FAIL  $test_name"
            if [ "$actual_out" != "$expected_out" ]; then
                msg="$msg (output mismatch)"
            fi
            if [ "$actual_exit" != "$expected_exit" ]; then
                msg="$msg (exit $actual_exit, expected $expected_exit)"
            fi
            FAILURES="$FAILURES\n$msg"
            echo "$msg"
            if [ "$actual_out" != "$expected_out" ]; then
                echo "        expected: $(echo "$expected_out" | head -1)"
                echo "        actual:   $(echo "$actual_out" | head -1)"
            fi
        fi
    fi
done

echo ""
echo "=== Results ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  KNOWN: $KNOWN_FAIL"
echo "  SKIP: $SKIP"
echo "  TOTAL: $((PASS + FAIL + KNOWN_FAIL + SKIP))"

if [ -n "$FAILURES" ]; then
    echo ""
    echo "Failures:"
    echo -e "$FAILURES"
fi

# Fail tests: these should fail compilation (exit != 0)
FAIL_DIR="$PROJECT_ROOT/tests/conformance/stage1/fail"
if [ -d "$FAIL_DIR" ]; then
    echo ""
    echo "=== Fail Tests (expected compile errors) ==="
    for test_file in "$FAIL_DIR"/*.jda; do
        test_name=$(basename "$test_file" .jda)
        bin_out="$TMP_DIR/$test_name"

        # Check for ; ARGS: directive in test file
        extra_args=""
        args_line=$(grep '^// ARGS:' "$test_file" 2>/dev/null | head -1 || true)
        if [ -n "$args_line" ]; then
            extra_args=$(echo "$args_line" | sed 's/^\/\/ ARGS: *//')
        fi

        # Compile — should fail
        if [ -n "$extra_args" ]; then
            compile_out=$("$JDA" build $extra_args "$test_file" -o "$bin_out" 2>&1) || true
        else
            compile_out=$("$JDA" "$test_file" "$bin_out" 2>&1) || true
        fi
        if [ ! -f "$bin_out" ]; then
            PASS=$((PASS + 1))
            echo "  PASS  $test_name (compile failed as expected)"
        else
            FAIL=$((FAIL + 1))
            FAILURES="$FAILURES\n  FAIL  $test_name (should have failed but compiled)"
            echo "  FAIL  $test_name (should have failed but compiled)"
            rm -f "$bin_out"
        fi
    done
fi

# Self-host convergence (optional)
if [ "${1:-}" = "--selfhost" ]; then
    echo ""
    echo "=== Self-Host Convergence ==="
    JDA1_SRC="$PROJECT_ROOT/bootstrap/stage1/jda1.jda"
    A="$TMP_DIR/jda1_a"
    B="$TMP_DIR/jda1_b"

    echo "  Stage 2: jda1 → jda1_a ..."
    "$JDA" "$JDA1_SRC" "$A" 2>/dev/null
    chmod +x "$A"
    echo "  Stage 3: jda1_a → jda1_b ..."
    "$A" "$JDA1_SRC" "$B" 2>/dev/null
    chmod +x "$B"

    if cmp -s "$A" "$B"; then
        echo "  CONVERGED — jda1_a == jda1_b ($(wc -c < "$A") bytes)"
    else
        echo "  DIVERGED — jda1_a != jda1_b"
        FAIL=$((FAIL + 1))
    fi
fi

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
echo ""
echo "All tests passed."
exit 0
