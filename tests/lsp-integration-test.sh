#!/bin/bash
# Integration test for jda-lsp.sh
# Sends LSP JSON-RPC messages and verifies responses

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LSP="$SCRIPT_DIR/../tools/jda-lsp.sh"

PASS=0
FAIL=0

# Send an LSP message (Content-Length header + body)
lsp_msg() {
    local body="$1"
    local len=${#body}
    printf "Content-Length: %d\r\n\r\n%s" "$len" "$body"
}

# Run a single LSP session with a sequence of messages, capture all output
run_lsp_session() {
    local input="$1"
    echo "$input" | timeout 5 "$LSP" 2>/dev/null || true
}

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

# ─── Test 1: Initialize ──────────────────────────────────────────────────────

test_initialize() {
    local init_msg='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"rootUri":"file:///tmp/test"}}'
    local exit_msg='{"jsonrpc":"2.0","method":"exit","params":{}}'
    local input
    input="$(lsp_msg "$init_msg")$(lsp_msg "$exit_msg")"

    local output
    output="$(echo "$input" | timeout 5 "$LSP" 2>/dev/null || true)"

    # Check response contains capabilities
    echo "$output" | grep -q "textDocumentSync" || return 1
    echo "$output" | grep -q "hoverProvider" || return 1
    echo "$output" | grep -q "completionProvider" || return 1
    echo "$output" | grep -q "definitionProvider" || return 1
    echo "$output" | grep -q "jda-lsp" || return 1
}

# ─── Test 2: Shutdown ────────────────────────────────────────────────────────

test_shutdown() {
    local init_msg='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
    local shutdown_msg='{"jsonrpc":"2.0","id":2,"method":"shutdown","params":{}}'
    local exit_msg='{"jsonrpc":"2.0","method":"exit","params":{}}'
    local input
    input="$(lsp_msg "$init_msg")$(lsp_msg "$shutdown_msg")$(lsp_msg "$exit_msg")"

    local output
    output="$(echo "$input" | timeout 5 "$LSP" 2>/dev/null || true)"

    # Should get response to shutdown (id:2)
    echo "$output" | grep -q '"id":2' || echo "$output" | grep -q '"id": 2' || return 1
}

# ─── Test 3: Document open + diagnostics ─────────────────────────────────────

test_did_open() {
    local init_msg='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
    local init_done='{"jsonrpc":"2.0","method":"initialized","params":{}}'
    local open_msg='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/test.jda","text":"fn main() -> i64 {\n    ret 0\n}\n","version":1}}}'
    local exit_msg='{"jsonrpc":"2.0","method":"exit","params":{}}'
    local input
    input="$(lsp_msg "$init_msg")$(lsp_msg "$init_done")$(lsp_msg "$open_msg")$(lsp_msg "$exit_msg")"

    local output
    output="$(echo "$input" | timeout 5 "$LSP" 2>/dev/null || true)"

    # Should get publishDiagnostics notification
    echo "$output" | grep -q "publishDiagnostics" || return 1
}

# ─── Test 4: Hover ───────────────────────────────────────────────────────────

test_hover() {
    local init_msg='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
    local init_done='{"jsonrpc":"2.0","method":"initialized","params":{}}'
    local open_msg='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/test.jda","text":"fn main() -> i64 {\n    let x = 42\n    ret x\n}\n","version":1}}}'
    # Hover over "fn" at line 0, col 0
    local hover_msg='{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///tmp/test.jda"},"position":{"line":0,"character":0}}}'
    local exit_msg='{"jsonrpc":"2.0","method":"exit","params":{}}'
    local input
    input="$(lsp_msg "$init_msg")$(lsp_msg "$init_done")$(lsp_msg "$open_msg")$(lsp_msg "$hover_msg")$(lsp_msg "$exit_msg")"

    local output
    output="$(echo "$input" | timeout 5 "$LSP" 2>/dev/null || true)"

    # Should get hover result with "fn" documentation
    echo "$output" | grep -q "declare a function" || return 1
}

# ─── Test 5: Completion ──────────────────────────────────────────────────────

test_completion() {
    local init_msg='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
    local open_msg='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/test.jda","text":"fn main() -> i64 {\n    le\n}\n","version":1}}}'
    # Complete at "le" — line 1, col 6
    local comp_msg='{"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///tmp/test.jda"},"position":{"line":1,"character":6}}}'
    local exit_msg='{"jsonrpc":"2.0","method":"exit","params":{}}'
    local input
    input="$(lsp_msg "$init_msg")$(lsp_msg "$open_msg")$(lsp_msg "$comp_msg")$(lsp_msg "$exit_msg")"

    local output
    output="$(echo "$input" | timeout 5 "$LSP" 2>/dev/null || true)"

    # Should suggest "let"
    echo "$output" | grep -q '"let"' || return 1
}

# ─── Test 6: Document symbols ────────────────────────────────────────────────

test_document_symbol() {
    local init_msg='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
    local open_msg='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/test.jda","text":"fn add(a: i64, b: i64) -> i64 {\n    ret a + b\n}\nfn main() -> i64 {\n    ret add(1, 2)\n}\n","version":1}}}'
    local sym_msg='{"jsonrpc":"2.0","id":2,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":"file:///tmp/test.jda"}}}'
    local exit_msg='{"jsonrpc":"2.0","method":"exit","params":{}}'
    local input
    input="$(lsp_msg "$init_msg")$(lsp_msg "$open_msg")$(lsp_msg "$sym_msg")$(lsp_msg "$exit_msg")"

    local output
    output="$(echo "$input" | timeout 5 "$LSP" 2>/dev/null || true)"

    # Should list both functions
    echo "$output" | grep -q '"add"' || return 1
    echo "$output" | grep -q '"main"' || return 1
}

# ─── Test 7: Go-to-definition ────────────────────────────────────────────────

test_definition() {
    local init_msg='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
    local open_msg='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/test.jda","text":"fn add(a: i64, b: i64) -> i64 {\n    ret a + b\n}\nfn main() -> i64 {\n    ret add(1, 2)\n}\n","version":1}}}'
    # Go-to-definition on "add" at line 4, col 8
    local def_msg='{"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"file:///tmp/test.jda"},"position":{"line":4,"character":8}}}'
    local exit_msg='{"jsonrpc":"2.0","method":"exit","params":{}}'
    local input
    input="$(lsp_msg "$init_msg")$(lsp_msg "$open_msg")$(lsp_msg "$def_msg")$(lsp_msg "$exit_msg")"

    local output
    output="$(echo "$input" | timeout 5 "$LSP" 2>/dev/null || true)"

    # Should point to line 0 (where fn add is defined)
    echo "$output" | grep -q '"line": 0' || echo "$output" | grep -q '"line":0' || return 1
}

# ─── Test 8: Formatting ──────────────────────────────────────────────────────

test_formatting() {
    local init_msg='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
    local open_msg='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/test.jda","text":"fn main() -> i64 {\nret 0\n}\n","version":1}}}'
    local fmt_msg='{"jsonrpc":"2.0","id":2,"method":"textDocument/formatting","params":{"textDocument":{"uri":"file:///tmp/test.jda"},"options":{"tabSize":4,"insertSpaces":true}}}'
    local exit_msg='{"jsonrpc":"2.0","method":"exit","params":{}}'
    local input
    input="$(lsp_msg "$init_msg")$(lsp_msg "$open_msg")$(lsp_msg "$fmt_msg")$(lsp_msg "$exit_msg")"

    local output
    output="$(echo "$input" | timeout 5 "$LSP" 2>/dev/null || true)"

    # Should have indented "ret 0" with 4 spaces
    echo "$output" | grep -q "    ret 0" || return 1
}

# ─── Run all tests ───────────────────────────────────────────────────────────

echo "jda-lsp integration tests"
echo "========================="

run_test "initialize returns capabilities" test_initialize
run_test "shutdown responds" test_shutdown
run_test "didOpen publishes diagnostics" test_did_open
run_test "hover shows keyword docs" test_hover
run_test "completion suggests keywords" test_completion
run_test "documentSymbol lists functions" test_document_symbol
run_test "definition finds fn declaration" test_definition
run_test "formatting indents code" test_formatting

echo ""
TOTAL=$((PASS + FAIL))
echo "Results: $PASS/$TOTAL passed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
