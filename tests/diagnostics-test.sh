#!/usr/bin/env bash
# Diagnostics test — the machine-readable contract of `--json` and `jda check`.
#
# Tools and models consume this output, so its shape is a contract:
#   - JSON goes to stderr on failure, stdout on success
#   - every diagnostic carries a stable JDA-* code
#   - exit status is 0 for ok, 1 for a compile error
#   - `check` compiles fully but writes no binary

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JDA="${JDA1_BIN:-$ROOT/bootstrap/stage0/jda1}"
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

PASS=0
FAIL=0

ok()   { echo "  PASS  $1"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL  $1"; shift; for l in "$@"; do echo "          $l"; done; FAIL=$((FAIL + 1)); }

if [ ! -x "$JDA" ]; then echo "SKIP: jda1 not found at $JDA"; exit 0; fi

cat > "$TMP_DIR/ok.jda" <<'JDA'
fn main() {
    print("hi")
}
JDA

cat > "$TMP_DIR/bad.jda" <<'JDA'
fn main() {
    let x = 1
    if x > 0 
        print("hi")
    }
}
JDA

echo "=== Diagnostics ==="

# 1. check on a good file succeeds and writes no binary
rm -f "$TMP_DIR/ok"
out=$("$JDA" check "$TMP_DIR/ok.jda" 2>/dev/null); rc=$?
if [ $rc -eq 0 ] && [ ! -f "$TMP_DIR/ok" ]; then ok "check: succeeds, writes no binary"
else bad "check: succeeds, writes no binary" "rc=$rc"; fi

# 2. check --json on a good file: ok:true on stdout
out=$("$JDA" check --json "$TMP_DIR/ok.jda" 2>/dev/null)
if printf '%s' "$out" | grep -q '"ok":true'; then ok "check --json: ok:true on stdout"
else bad "check --json: ok:true on stdout" "got: $out"; fi

# 3. failing compile: JSON on stderr, nothing on stdout, exit 1
errout=$("$JDA" check --json "$TMP_DIR/bad.jda" 2>&1 >/dev/null); rc=$?
stdout=$("$JDA" check --json "$TMP_DIR/bad.jda" 2>/dev/null)
if [ $rc -eq 1 ] && [ -z "$stdout" ] && printf '%s' "$errout" | grep -q '"ok":false'; then
    ok "error: JSON on stderr, clean stdout, exit 1"
else bad "error: JSON on stderr, clean stdout, exit 1" "rc=$rc" "stdout=[$stdout]"; fi

# 4. diagnostic carries a stable JDA-* code
if printf '%s' "$errout" | grep -qE '"code":"JDA-[A-Z][0-9]{3}"'; then ok "error: carries a JDA-* code"
else bad "error: carries a JDA-* code" "got: $errout"; fi

# 5. location fields are present and correct (line 4, col 9)
if printf '%s' "$errout" | grep -q '"line":4' && printf '%s' "$errout" | grep -q '"col":9'; then
    ok "error: reports line:col"
else bad "error: reports line:col" "got: $errout"; fi

# 6. it is valid JSON (when python is available)
if command -v python3 >/dev/null 2>&1; then
    if printf '%s' "$errout" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["schema"]==1; assert len(d["diagnostics"])==1' 2>/dev/null; then
        ok "error: output parses as JSON with schema 1"
    else bad "error: output parses as JSON with schema 1" "got: $errout"; fi
fi

# 7. human-readable mode is unchanged (no JSON leakage)
human=$("$JDA" check "$TMP_DIR/bad.jda" 2>&1 >/dev/null)
if printf '%s' "$human" | grep -q "error: expected" && ! printf '%s' "$human" | grep -q '"schema"'; then
    ok "default mode stays human-readable"
else bad "default mode stays human-readable" "got: $human"; fi

# 8. --emit-tokens produces valid JSON
if command -v python3 >/dev/null 2>&1; then
    out=$("$JDA" build --emit-tokens "$TMP_DIR/ok.jda" 2>/dev/null)
    if printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["kind"]=="tokens"; assert d["count"]>0' 2>/dev/null; then
        ok "--emit-tokens: valid JSON token stream"
    else bad "--emit-tokens: valid JSON token stream" "got: $(printf '%s' "$out" | head -c 120)"; fi

    # 9. --emit-ast lists top-level declarations
    out=$("$JDA" build --emit-ast "$TMP_DIR/ok.jda" 2>/dev/null)
    if printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["kind"]=="ast"; assert any(x["name"]=="main" for x in d["decls"])' 2>/dev/null; then
        ok "--emit-ast: valid JSON declaration list"
    else bad "--emit-ast: valid JSON declaration list" "got: $(printf '%s' "$out" | head -c 120)"; fi
fi

# 10. Every rejected-syntax case answers --json with contract-shaped JSON.
#
# The two fixtures above both fail through report_error_at, which was the only
# path that honoured --json; undefined functions and panic() printed prose, so a
# client parsing the stream got a bare line instead of an object. Sweeping the
# whole rejected/ corpus is what keeps that from coming back.
if command -v python3 >/dev/null 2>&1; then
    sweep_fail=0
    for src in "$ROOT"/tests/rejected/*.jda; do
        name=$(basename "$src" .jda)
        out=$("$JDA" check --json "$src" 2>&1 >/dev/null)
        if ! printf '%s' "$out" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d.get("schema")==1
assert d.get("ok") is False
assert d.get("diagnostics")
for x in d["diagnostics"]:
    assert str(x.get("code","")).startswith("JDA-")
    for k in ("severity","file","line","col","message"): assert k in x
' 2>/dev/null; then
            bad "rejected/$name answers --json with contract JSON" "got: $(printf '%s' "$out" | head -c 160)"
            sweep_fail=1
        fi
    done
    [ "$sweep_fail" -eq 0 ] && ok "every rejected/ case answers --json with contract JSON"
fi

echo ""
echo "=== Results ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
echo "All diagnostics tests passed."
