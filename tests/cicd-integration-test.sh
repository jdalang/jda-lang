#!/bin/bash
# Integration test for CI/CD & release pipeline components
# Tests: benchmark script, package script, install script, CI workflows

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

# ─── Test 1: CI workflow syntax ──────────────────────────────────────────────

test_ci_workflow() {
    [ -f "$ROOT/.github/workflows/ci.yml" ] || return 1
    grep -q "test-x86_64" "$ROOT/.github/workflows/ci.yml" || return 1
    grep -q "test-arm64" "$ROOT/.github/workflows/ci.yml" || return 1
    grep -q "test-macos" "$ROOT/.github/workflows/ci.yml" || return 1
    grep -q "benchmark" "$ROOT/.github/workflows/ci.yml" || return 1
}

# ─── Test 2: Release workflow syntax ─────────────────────────────────────────

test_release_workflow() {
    [ -f "$ROOT/.github/workflows/release.yml" ] || return 1
    grep -q "build-linux-x86_64" "$ROOT/.github/workflows/release.yml" || return 1
    grep -q "build-linux-arm64" "$ROOT/.github/workflows/release.yml" || return 1
    grep -q "build-macos" "$ROOT/.github/workflows/release.yml" || return 1
    grep -q "checksums.txt" "$ROOT/.github/workflows/release.yml" || return 1
}

# ─── Test 3: Bench script exists and is valid ────────────────────────────────

test_bench_script() {
    [ -f "$ROOT/tools/bench-ci.sh" ] || return 1
    grep -q "self_compile_ms" "$ROOT/tools/bench-ci.sh" || return 1
    grep -q "fib35_ms" "$ROOT/tools/bench-ci.sh" || return 1
    grep -q "THRESHOLD" "$ROOT/tools/bench-ci.sh" || return 1
}

# ─── Test 4: Baseline file ──────────────────────────────────────────────────

test_baseline() {
    [ -f "$ROOT/tools/bench-baseline.json" ] || return 1
    grep -q "self_compile_ms" "$ROOT/tools/bench-baseline.json" || return 1
    grep -q "fib35_ms" "$ROOT/tools/bench-baseline.json" || return 1
    grep -q "binary_size" "$ROOT/tools/bench-baseline.json" || return 1
}

# ─── Test 5: Package script multi-platform ───────────────────────────────────

test_package_platforms() {
    [ -f "$ROOT/tools/package-release.sh" ] || return 1
    grep -q "arm64" "$ROOT/tools/package-release.sh" || return 1
    grep -q "macos" "$ROOT/tools/package-release.sh" || return 1
    grep -q "x86_64" "$ROOT/tools/package-release.sh" || return 1
}

# ─── Test 6: Package script runs (macOS target) ─────────────────────────────

test_package_run() {
    bash "$ROOT/tools/package-release.sh" "0.0.0-test" macos > /dev/null 2>&1 || return 1
    [ -f "$ROOT/dist/jda-0.0.0-test-macos.tar.gz" ] || return 1
    rm -rf "$ROOT/dist"
}

# ─── Test 7: Install script multi-platform ───────────────────────────────────

test_install_multiplatform() {
    [ -f "$ROOT/install.sh" ] || return 1
    grep -q "linux-x86_64" "$ROOT/install.sh" || return 1
    grep -q "linux-arm64" "$ROOT/install.sh" || return 1
    grep -q "macos" "$ROOT/install.sh" || return 1
    grep -q "Darwin" "$ROOT/install.sh" || return 1
}

# ─── Test 8: Install script platform detection ──────────────────────────────

test_install_detection() {
    grep -q "uname -m" "$ROOT/install.sh" || return 1
    grep -q "uname -s" "$ROOT/install.sh" || return 1
    grep -q "aarch64" "$ROOT/install.sh" || return 1
}

# ─── Test 9: Install script checksum verify ──────────────────────────────────

test_install_checksum() {
    grep -q "sha256sum" "$ROOT/install.sh" || return 1
    grep -q "shasum" "$ROOT/install.sh" || return 1
    grep -q "Checksum verified" "$ROOT/install.sh" || return 1
}

# ─── Test 10: Release includes tools ─────────────────────────────────────────

test_release_tools() {
    grep -q "jda-fmt" "$ROOT/.github/workflows/release.yml" || return 1
    grep -q "tools/" "$ROOT/.github/workflows/release.yml" || return 1
    grep -q "stdlib/" "$ROOT/.github/workflows/release.yml" || return 1
}

# ─── Test 11: Test runner exists ─────────────────────────────────────────────

test_runner_exists() {
    [ -f "$ROOT/tools/run_tests.sh" ] || return 1
    [ -x "$ROOT/tools/run_tests.sh" ] || return 1
    grep -q "PASS" "$ROOT/tools/run_tests.sh" || return 1
    grep -q "FAIL" "$ROOT/tools/run_tests.sh" || return 1
}

# ─── Test 12: Convergence in CI ──────────────────────────────────────────────

test_convergence_ci() {
    grep -q "convergence" "$ROOT/.github/workflows/ci.yml" || return 1
    grep -q "cmp" "$ROOT/.github/workflows/ci.yml" || return 1
    grep -q "CONVERGED" "$ROOT/.github/workflows/ci.yml" || return 1
}

# ─── Run all ──────────────────────────────────────────────────────────────────

echo "CI/CD integration tests"
echo "======================="

run_test "CI workflow structure" test_ci_workflow
run_test "Release workflow structure" test_release_workflow
run_test "Benchmark script" test_bench_script
run_test "Benchmark baseline" test_baseline
run_test "Package multi-platform" test_package_platforms
run_test "Package runs" test_package_run
run_test "Install multi-platform" test_install_multiplatform
run_test "Install platform detection" test_install_detection
run_test "Install checksum verify" test_install_checksum
run_test "Release includes tools" test_release_tools
run_test "Test runner exists" test_runner_exists
run_test "Convergence in CI" test_convergence_ci

echo ""
TOTAL=$((PASS + FAIL))
echo "Results: $PASS/$TOTAL passed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
