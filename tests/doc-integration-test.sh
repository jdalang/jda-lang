#!/bin/bash
# Integration test for jda-doc.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOC="$SCRIPT_DIR/../tools/jda-doc.sh"
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

# Create test source files
cat > "$TMP_DIR/math.jda" <<'EOF'
;; Math utility library.

;; Add two integers.
fn add(a: i64, b: i64) -> i64 {
  ret a + b
}

;; Subtract b from a.
fn sub(a: i64, b: i64) -> i64 {
  ret a - b
}

;; A 2D coordinate.
struct Point {
  x: i64
  y: i64
}

;; Color options.
enum Color {
  Red
  Green
  Blue
}

;; Pi approximation.
const PI = 3

fn main() -> i64 {
  ret 0
}
EOF

cat > "$TMP_DIR/utils.jda" <<'EOF'
;; Utility functions.

;; Return the larger value.
fn max_val(a: i64, b: i64) -> i64 {
  if a > b { ret a }
  ret b
}

fn main() -> i64 {
  ret 0
}
EOF

# ─── Test 1: Generates index.html ────────────────────────────────────────────

test_index() {
    "$DOC" --output "$TMP_DIR/out1" "$TMP_DIR/math.jda"
    [ -f "$TMP_DIR/out1/index.html" ]
}

# ─── Test 2: Generates module page ───────────────────────────────────────────

test_module_page() {
    "$DOC" --output "$TMP_DIR/out2" "$TMP_DIR/math.jda"
    [ -f "$TMP_DIR/out2/math.html" ]
}

# ─── Test 3: Generates style.css ─────────────────────────────────────────────

test_css() {
    "$DOC" --output "$TMP_DIR/out3" "$TMP_DIR/math.jda"
    [ -f "$TMP_DIR/out3/style.css" ]
}

# ─── Test 4: Extracts functions ──────────────────────────────────────────────

test_functions() {
    "$DOC" --output "$TMP_DIR/out4" "$TMP_DIR/math.jda"
    grep -q '"add"' "$TMP_DIR/out4/math.html" || grep -q '>add<' "$TMP_DIR/out4/math.html"
}

# ─── Test 5: Extracts doc comments ───────────────────────────────────────────

test_doc_comments() {
    "$DOC" --output "$TMP_DIR/out5" "$TMP_DIR/math.jda"
    grep -q "Add two integers" "$TMP_DIR/out5/math.html"
}

# ─── Test 6: Extracts structs ────────────────────────────────────────────────

test_structs() {
    "$DOC" --output "$TMP_DIR/out6" "$TMP_DIR/math.jda"
    grep -q "Point" "$TMP_DIR/out6/math.html"
    grep -q "2D coordinate" "$TMP_DIR/out6/math.html"
}

# ─── Test 7: Extracts enums ──────────────────────────────────────────────────

test_enums() {
    "$DOC" --output "$TMP_DIR/out7" "$TMP_DIR/math.jda"
    grep -q "Color" "$TMP_DIR/out7/math.html"
    grep -q "Color options" "$TMP_DIR/out7/math.html"
}

# ─── Test 8: Extracts constants ──────────────────────────────────────────────

test_constants() {
    "$DOC" --output "$TMP_DIR/out8" "$TMP_DIR/math.jda"
    grep -q "PI" "$TMP_DIR/out8/math.html"
}

# ─── Test 9: JSON output ─────────────────────────────────────────────────────

test_json() {
    local output
    output="$("$DOC" --json "$TMP_DIR/math.jda")"
    echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert len(d['math']) >= 6"
}

# ─── Test 10: Directory mode ─────────────────────────────────────────────────

test_directory() {
    "$DOC" --output "$TMP_DIR/out10" "$TMP_DIR/"
    [ -f "$TMP_DIR/out10/math.html" ] && [ -f "$TMP_DIR/out10/utils.html" ]
}

# ─── Test 11: Cross-reference links ──────────────────────────────────────────

test_cross_ref() {
    "$DOC" --output "$TMP_DIR/out11" "$TMP_DIR/"
    # Index should link to module pages
    grep -q 'math.html' "$TMP_DIR/out11/index.html"
    grep -q 'utils.html' "$TMP_DIR/out11/index.html"
}

# ─── Test 12: Source line links ───────────────────────────────────────────────

test_source_links() {
    "$DOC" --output "$TMP_DIR/out12" "$TMP_DIR/math.jda"
    # Should include source file:line references
    grep -q 'math.jda:' "$TMP_DIR/out12/math.html"
}

# ─── Run all ──────────────────────────────────────────────────────────────────

echo "jda-doc integration tests"
echo "========================="

run_test "generates index.html" test_index
run_test "generates module page" test_module_page
run_test "generates style.css" test_css
run_test "extracts functions" test_functions
run_test "extracts doc comments" test_doc_comments
run_test "extracts structs" test_structs
run_test "extracts enums" test_enums
run_test "extracts constants" test_constants
run_test "JSON output mode" test_json
run_test "directory mode" test_directory
run_test "cross-reference links" test_cross_ref
run_test "source line links" test_source_links

echo ""
TOTAL=$((PASS + FAIL))
echo "Results: $PASS/$TOTAL passed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
