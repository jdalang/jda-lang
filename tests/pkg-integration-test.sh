#!/bin/bash
# Integration test for jda-pkg.sh
# Tests: init, add, build, deps, lockfile generation
#
# Requires: git, the jda compiler accessible via JDA env var or default path

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG="$SCRIPT_DIR/../tools/jda-pkg.sh"
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

PASS=0
FAIL=0

run_test() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  PASS  $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $name"
        FAIL=$((FAIL + 1))
    fi
}

# ─── Test 1: init ─────────────────────────────────────────────────────────────

test_init() {
    local dir="$TMP_DIR/test-init"
    mkdir -p "$dir"
    (cd "$dir" && "$PKG" init)
    [ -f "$dir/jda.toml" ] || return 1
    [ -f "$dir/src/main.jda" ] || return 1
    grep -q '\[package\]' "$dir/jda.toml" || return 1
    grep -q '\[build\]' "$dir/jda.toml" || return 1
    grep -q '\[dependencies\]' "$dir/jda.toml" || return 1
}

# ─── Test 2: init fails if jda.toml exists ────────────────────────────────────

test_init_exists() {
    local dir="$TMP_DIR/test-init-dup"
    mkdir -p "$dir"
    (cd "$dir" && "$PKG" init)
    ! (cd "$dir" && "$PKG" init 2>/dev/null)
}

# ─── Test 3: add dependency ───────────────────────────────────────────────────

test_add() {
    local dir="$TMP_DIR/test-add"
    mkdir -p "$dir"
    (cd "$dir" && "$PKG" init)
    (cd "$dir" && "$PKG" add mathlib https://github.com/example/mathlib.git v1.0.0)
    grep -q 'mathlib' "$dir/jda.toml" || return 1
    grep -q 'https://github.com/example/mathlib.git' "$dir/jda.toml" || return 1
    grep -q 'v1.0.0' "$dir/jda.toml" || return 1
}

# ─── Test 4: add duplicate fails ─────────────────────────────────────────────

test_add_dup() {
    local dir="$TMP_DIR/test-add-dup"
    mkdir -p "$dir"
    (cd "$dir" && "$PKG" init)
    (cd "$dir" && "$PKG" add mylib https://example.com/mylib.git v1.0)
    ! (cd "$dir" && "$PKG" add mylib https://example.com/mylib.git v2.0 2>/dev/null)
}

# ─── Test 5: build with no deps ──────────────────────────────────────────────

test_build_no_deps() {
    local dir="$TMP_DIR/test-build-nodeps"
    mkdir -p "$dir/src" "$dir/build"
    cat > "$dir/jda.toml" <<'EOF'
[package]
name = "testpkg"
version = "0.1.0"

[build]
entry = "src/main.jda"
output = "build/testpkg"

[dependencies]
EOF
    cat > "$dir/src/main.jda" <<'EOF'
fn main() -> i64 {
    print "hello"
    ret 0
}
EOF
    (cd "$dir" && "$PKG" build)
    [ -f "$dir/build/testpkg" ] || return 1
}

# ─── Test 6: build with local git dep ────────────────────────────────────────

test_build_with_dep() {
    # Create a local git repo as a "dependency"
    local dep_repo="$TMP_DIR/dep-repo"
    mkdir -p "$dep_repo"
    (cd "$dep_repo" && git init --quiet && \
     cat > lib.jda <<'JDAEOF'
fn double(x: i64) -> i64 {
    ret x + x
}
JDAEOF
     git add lib.jda && git commit --quiet -m "initial")

    # Create project that uses it
    local dir="$TMP_DIR/test-build-dep"
    mkdir -p "$dir/src" "$dir/build"
    cat > "$dir/jda.toml" <<EOF
[package]
name = "testdep"
version = "0.1.0"

[build]
entry = "src/main.jda"
output = "build/testdep"

[dependencies]
mymath = { git = "$dep_repo", tag = "main" }
EOF
    cat > "$dir/src/main.jda" <<'JDAEOF'
fn main() -> i64 {
    let r = double(21)
    if r != 42 {
        syscall(60, 1, 0, 0)
    }
    print "dep ok"
    ret 0
}
JDAEOF
    (cd "$dir" && "$PKG" build)
    [ -f "$dir/build/testdep" ] || return 1
    # Verify lockfile was created
    [ -f "$dir/jda.lock" ] || return 1
    grep -q 'mymath' "$dir/jda.lock" || return 1
}

# ─── Test 7: deps command ────────────────────────────────────────────────────

test_deps() {
    local dir="$TMP_DIR/test-deps"
    mkdir -p "$dir"
    cat > "$dir/jda.toml" <<'EOF'
[package]
name = "testdeps"
version = "0.1.0"

[build]
entry = "src/main.jda"
output = "build/testdeps"

[dependencies]
EOF
    local output
    output="$(cd "$dir" && "$PKG" deps)"
    echo "$output" | grep -q 'testdeps' || return 1
}

# ─── Test 8: manifest parsing ────────────────────────────────────────────────

test_manifest_parse() {
    local dir="$TMP_DIR/test-manifest"
    mkdir -p "$dir/src" "$dir/build"
    cat > "$dir/jda.toml" <<'EOF'
[package]
name = "mypkg"
version = "2.3.1"

[build]
entry = "src/app.jda"
output = "build/app"

[dependencies]
EOF
    cat > "$dir/src/app.jda" <<'JDAEOF'
fn main() -> i64 {
    print "manifest ok"
    ret 0
}
JDAEOF
    (cd "$dir" && "$PKG" build)
    [ -f "$dir/build/app" ] || return 1
}

# ─── Run all tests ───────────────────────────────────────────────────────────

echo "jda-pkg integration tests"
echo "========================="

run_test "init creates jda.toml" test_init
run_test "init fails if exists" test_init_exists
run_test "add dependency" test_add
run_test "add duplicate fails" test_add_dup
run_test "build with no deps" test_build_no_deps
run_test "build with local git dep" test_build_with_dep
run_test "deps command" test_deps
run_test "manifest parsing" test_manifest_parse

echo ""
TOTAL=$((PASS + FAIL))
echo "Results: $PASS/$TOTAL passed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
