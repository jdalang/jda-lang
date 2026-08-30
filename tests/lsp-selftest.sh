#!/usr/bin/env bash
# Compiles tools/lsp.jda, runs its built-in selftest, and drives one real
# LSP session over stdin/stdout.
#
# The selftest covers the analysis and the JSON encoder. The session below is
# what catches the things a unit test cannot: message framing, dispatch, and
# whether the text an editor actually sends survives being stored and read back.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JDA="${JDA1_BIN:-$ROOT/bootstrap/stage0/jda1}"
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

if [ ! -x "$JDA" ]; then echo "SKIP: jda1 not found at $JDA"; exit 0; fi

echo "=== lsp.jda selftest ==="

cat "$ROOT/stdlib/prelude.jda" "$ROOT/stdlib/json.jda" > "$TMP_DIR/inc.jda"

if ! "$JDA" build --include "$TMP_DIR/inc.jda" "$ROOT/tools/lsp.jda" -o "$TMP_DIR/lsp" 2>"$TMP_DIR/err"; then
    echo "  FAIL  tools/lsp.jda does not compile"
    sed 's/^/          /' "$TMP_DIR/err"
    exit 1
fi
echo "  PASS  tools/lsp.jda compiles"
chmod +x "$TMP_DIR/lsp"

out=$("$TMP_DIR/lsp" selftest 2>&1); rc=$?
if [ $rc -ne 0 ] || ! printf '%s' "$out" | grep -q "^selftest: all ok$"; then
    echo "  FAIL  selftest (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/          /'
    exit 1
fi
echo "  PASS  selftest: all assertions hold"

if ! command -v python3 >/dev/null 2>&1; then
    echo "  SKIP  protocol session (python3 not available)"
    echo ""
    echo "All lsp.jda selftests passed."
    exit 0
fi

python3 - "$TMP_DIR/lsp" <<'PY'
import json, subprocess, sys

def frame(o):
    b = json.dumps(o).encode()
    return b"Content-Length: %d\r\n\r\n" % len(b) + b

DOC = "fn helper() {\n}\n\nfn main() {\n\thelper()  \n}\n"
URI = "file:///w/a.jda"
msgs = [
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"rootUri":"file:///w"}},
    {"jsonrpc":"2.0","method":"initialized","params":{}},
    {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{
        "textDocument":{"uri":URI,"languageId":"jda","version":1,"text":DOC}}},
    {"jsonrpc":"2.0","id":2,"method":"textDocument/documentSymbol","params":{
        "textDocument":{"uri":URI}}},
    {"jsonrpc":"2.0","id":3,"method":"textDocument/definition","params":{
        "textDocument":{"uri":URI},"position":{"line":4,"character":3}}},
    {"jsonrpc":"2.0","id":4,"method":"textDocument/hover","params":{
        "textDocument":{"uri":URI},"position":{"line":0,"character":1}}},
    {"jsonrpc":"2.0","id":5,"method":"textDocument/completion","params":{
        "textDocument":{"uri":URI},"position":{"line":4,"character":7}}},
    {"jsonrpc":"2.0","id":6,"method":"workspace/symbol","params":{"query":"help"}},
    {"jsonrpc":"2.0","id":7,"method":"textDocument/formatting","params":{
        "textDocument":{"uri":URI}}},
    {"jsonrpc":"2.0","id":8,"method":"nope/nothing","params":{}},
    {"jsonrpc":"2.0","id":9,"method":"shutdown"},
    {"jsonrpc":"2.0","method":"exit"},
]

p = subprocess.run([sys.argv[1]], input=b"".join(frame(m) for m in msgs),
                   capture_output=True, timeout=60)
out, fails = p.stdout, []

def bad(m): fails.append(m)

if p.returncode != 0:
    bad("server exited %d" % p.returncode)

# Unframe every response and require the stream to end exactly on a boundary.
msgs_out, i = [], 0
while i < len(out):
    j = out.find(b"\r\n\r\n", i)
    if j < 0:
        bad("trailing bytes with no header"); break
    try:
        n = int(out[i:j].decode().split("Content-Length:")[1].strip().split()[0])
    except Exception:
        bad("unparseable header: %r" % out[i:j][:80]); break
    body = out[j+4:j+4+n]
    if len(body) != n:
        bad("Content-Length %d but only %d bytes remain" % (n, len(body))); break
    try:
        msgs_out.append(json.loads(body))
    except Exception as e:
        bad("response is not valid JSON: %s" % e)
    i = j + 4 + n

by_id = {m["id"]: m for m in msgs_out if "id" in m}
notes = [m for m in msgs_out if "method" in m]

for m in msgs_out:
    if m.get("jsonrpc") != "2.0":
        bad("response missing jsonrpc 2.0")

caps = by_id.get(1, {}).get("result", {}).get("capabilities")
if not caps or not caps.get("hoverProvider") or not caps.get("definitionProvider"):
    bad("initialize did not advertise capabilities")

diags = [n for n in notes if n["method"] == "textDocument/publishDiagnostics"]
if not diags:
    bad("no diagnostics published on didOpen")
else:
    codes = sorted(d["code"] for d in diags[0]["params"]["diagnostics"])
    if codes != ["W098", "W099"]:
        bad("expected the tab and trailing-whitespace warnings, got %s" % codes)

names = sorted(s["name"] for s in by_id.get(2, {}).get("result", []))
if names != ["helper", "main"]:
    bad("documentSymbol returned %s" % names)

d = by_id.get(3, {}).get("result")
if not d or d.get("uri") != URI or d["range"]["start"]["line"] != 0:
    bad("definition of helper did not resolve to line 0: %r" % (d,))

h = by_id.get(4, {}).get("result")
if not h or "**fn**" not in h.get("contents", {}).get("value", ""):
    bad("hover over `fn` returned no documentation")

labels = [c["label"] for c in by_id.get(5, {}).get("result", [])]
if labels != ["helper"]:
    bad("completion for prefix `helper` returned %s" % labels)

ws = [s["name"] for s in by_id.get(6, {}).get("result", [])]
if ws != ["helper"]:
    bad("workspace/symbol for `help` returned %s" % ws)

edits = by_id.get(7, {}).get("result")
want = "fn helper() {\n}\n\nfn main() {\n    helper()\n}\n"
if not edits or edits[0]["newText"] != want:
    got = edits[0]["newText"] if edits else None
    bad("formatting produced %r" % got)

err = by_id.get(8, {}).get("error")
if not err or err.get("code") != -32601:
    bad("unknown method did not return -32601: %r" % (err,))

if 9 not in by_id or by_id[9].get("result") is not None:
    bad("shutdown did not return a null result")

if fails:
    for f in fails:
        print("  FAIL  " + f)
    sys.exit(1)
print("  PASS  protocol session: framing, dispatch and all nine responses")
PY
rc=$?
[ $rc -eq 0 ] || exit 1

echo ""
echo "All lsp.jda selftests passed."
