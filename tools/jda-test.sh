#!/bin/bash
# jda-test — run Jda test files using assert_eq / assert_ne / assert_true / assert_close
#
# Usage:
#   tools/jda-test.sh <file.jda>            # run a single test file
#   tools/jda-test.sh <dir/>                # run all .jda files in a directory
#
# Test files can define fn test_* functions; jda-test generates a main() wrapper
# that calls each discovered test function in order.
# If the file already defines main(), it is compiled and run directly.
#
# Assertion runtime functions (assert_eq, assert_ne, assert_true, assert_close)
# are automatically prepended if the test file uses them but doesn't define them.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JDA="${JDA:-$SCRIPT_DIR/../bootstrap/stage0/jda1}"
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

if [ $# -lt 1 ]; then
    echo "usage: jda-test.sh <file.jda | directory>" >&2
    exit 1
fi

TARGET="$1"

# Assertion runtime — prepended to test files that use assertions without defining them
ASSERT_RUNTIME='fn assert_eq(a: i64, b: i64) {
    if a != b {
        syscall(60, 1, 0, 0)
    }
}
fn assert_ne(a: i64, b: i64) {
    if a == b {
        syscall(60, 1, 0, 0)
    }
}
fn assert_true(val: i64) {
    if val == 0 {
        syscall(60, 1, 0, 0)
    }
}
fn assert_close(a: i64, b: i64) {
    if a != b {
        syscall(60, 1, 0, 0)
    }
}
'

# Collect test files
declare -a TEST_FILES=()
if [ -d "$TARGET" ]; then
    while IFS= read -r f; do
        TEST_FILES+=("$f")
    done < <(find "$TARGET" -name "*.jda" | sort)
else
    TEST_FILES=("$TARGET")
fi

PASS=0
FAIL=0
TOTAL=${#TEST_FILES[@]}

for test_file in "${TEST_FILES[@]}"; do
    test_name=$(basename "$test_file" .jda)
    bin_out="$TMP_DIR/$test_name"

    # Check if file has fn test_* functions (and no main)
    has_tests=$(grep -c '^fn test_' "$test_file" 2>/dev/null || echo 0)
    has_main=$(grep -c '^fn main' "$test_file" 2>/dev/null || echo 0)

    src_to_compile="$test_file"

    # Check if we need to prepend assertion runtime
    uses_assert=$(grep -c 'assert_eq\|assert_ne\|assert_true\|assert_close' "$test_file" 2>/dev/null || echo 0)
    defines_assert=$(grep -c '^fn assert_' "$test_file" 2>/dev/null || echo 0)
    needs_runtime=0
    if [ "$uses_assert" -gt 0 ] && [ "$defines_assert" -eq 0 ]; then
        needs_runtime=1
    fi

    if [ "$has_tests" -gt 0 ] && [ "$has_main" -eq 0 ]; then
        # Generate a wrapper main() that calls all test_ functions
        wrapper="$TMP_DIR/${test_name}_wrapper.jda"
        if [ "$needs_runtime" -eq 1 ]; then
            printf '%s\n' "$ASSERT_RUNTIME" > "$wrapper"
        else
            : > "$wrapper"
        fi
        cat "$test_file" >> "$wrapper"
        printf '\nfn main() -> i64 {\n' >> "$wrapper"
        grep '^fn test_' "$test_file" | sed 's/^fn \([a-z_0-9]*\)(.*$/  \1()/' >> "$wrapper"
        printf '  ret 0\n}\n' >> "$wrapper"
        src_to_compile="$wrapper"
    elif [ "$needs_runtime" -eq 1 ]; then
        wrapper="$TMP_DIR/${test_name}_wrapper.jda"
        printf '%s\n' "$ASSERT_RUNTIME" > "$wrapper"
        cat "$test_file" >> "$wrapper"
        src_to_compile="$wrapper"
    fi

    # Compile
    if ! "$JDA" "$src_to_compile" "$bin_out" 2>/dev/null; then
        echo "  FAIL  $test_name (compile error)"
        FAIL=$((FAIL + 1))
        continue
    fi
    chmod +x "$bin_out"

    # Run
    if "$bin_out" 2>&1; then
        echo "  PASS  $test_name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $test_name (runtime failure)"
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "Results: $PASS/$TOTAL passed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
