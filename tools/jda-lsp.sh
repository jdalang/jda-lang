#!/usr/bin/env python3
"""
jda-lsp — Language Server Protocol server for Jda

Implements LSP 3.17 over stdin/stdout (JSON-RPC 2.0).
Transport: Content-Length: <n>\r\n\r\n<json>

Capabilities:
  - textDocument/didOpen, didChange, didClose
  - textDocument/publishDiagnostics (basic syntax checks)
  - textDocument/hover (keyword documentation)
  - textDocument/completion (keywords + symbols in scope)
  - textDocument/definition (go-to-definition for fn/struct/enum/const)
  - textDocument/documentSymbol (outline view)
  - textDocument/formatting (indent normalization)
  - workspace/symbol

Usage:
  Invoked by editors via config: "command": ["tools/jda-lsp.sh"]
"""

import sys
import json
import os
import re

LOG_FILE = os.environ.get("JDA_LSP_LOG", "")

def log(msg):
    if LOG_FILE:
        with open(LOG_FILE, "a") as f:
            f.write(f"{msg}\n")

# ─── Document store ──────────────────────────────────────────────────────────

docs = {}  # uri -> text

# ─── LSP transport ────────────────────────────────────────────────────────────

def read_message():
    """Read one LSP message from stdin."""
    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        line = line.decode("utf-8").rstrip("\r\n")
        if line == "":
            break
        if ":" in line:
            key, val = line.split(":", 1)
            headers[key.strip()] = val.strip()

    content_length = int(headers.get("Content-Length", "0"))
    if content_length == 0:
        return None

    body = sys.stdin.buffer.read(content_length)
    return json.loads(body.decode("utf-8"))

def send_message(msg):
    """Send an LSP message to stdout."""
    body = json.dumps(msg, ensure_ascii=False)
    header = f"Content-Length: {len(body.encode('utf-8'))}\r\n\r\n"
    sys.stdout.buffer.write(header.encode("utf-8"))
    sys.stdout.buffer.write(body.encode("utf-8"))
    sys.stdout.buffer.flush()

def send_response(req_id, result):
    send_message({"jsonrpc": "2.0", "id": req_id, "result": result})

def send_error(req_id, code, message):
    send_message({"jsonrpc": "2.0", "id": req_id, "error": {"code": code, "message": message}})

def send_notification(method, params):
    send_message({"jsonrpc": "2.0", "method": method, "params": params})

# ─── Source analysis ──────────────────────────────────────────────────────────

def is_ident_char(c):
    return c.isalnum() or c == "_"

def word_at(text, line, col):
    lines = text.split("\n")
    if line >= len(lines):
        return ""
    ln = lines[line]
    if col >= len(ln):
        return ""
    start = col
    end = col
    while start > 0 and is_ident_char(ln[start - 1]):
        start -= 1
    while end < len(ln) and is_ident_char(ln[end]):
        end += 1
    return ln[start:end]

def word_before(text, line, col):
    lines = text.split("\n")
    if line >= len(lines):
        return ""
    ln = lines[line]
    end = min(col, len(ln))
    start = end
    while start > 0 and is_ident_char(ln[start - 1]):
        start -= 1
    return ln[start:end]

def extract_symbols(text):
    """Extract top-level symbols (fn, struct, enum, const, impl)."""
    symbols = []
    for i, line in enumerate(text.split("\n")):
        stripped = line.strip()
        name = ""
        kind = 0
        if stripped.startswith("fn "):
            m = re.match(r"fn\s+([a-zA-Z_]\w*)", stripped)
            if m:
                name, kind = m.group(1), 12  # Function
        elif stripped.startswith("struct "):
            m = re.match(r"struct\s+([a-zA-Z_]\w*)", stripped)
            if m:
                name, kind = m.group(1), 23  # Struct
        elif stripped.startswith("enum "):
            m = re.match(r"enum\s+([a-zA-Z_]\w*)", stripped)
            if m:
                name, kind = m.group(1), 10  # Enum
        elif stripped.startswith("const "):
            m = re.match(r"const\s+([a-zA-Z_]\w*)", stripped)
            if m:
                name, kind = m.group(1), 14  # Constant
        elif stripped.startswith("impl "):
            m = re.match(r"impl\s+([a-zA-Z_]\w*)", stripped)
            if m:
                name, kind = m.group(1), 11  # Interface
        if name and kind:
            col = line.find(name)
            symbols.append({"name": name, "kind": kind, "line": i, "col": col})
    return symbols

def find_definition(text, word):
    """Find definition of word in text. Returns (line, col) or None."""
    if not word:
        return None
    prefixes = [f"fn {word}(", f"struct {word} ", f"struct {word}{{",
                f"enum {word} ", f"enum {word}{{", f"const {word} "]
    for i, line in enumerate(text.split("\n")):
        stripped = line.strip()
        for p in prefixes:
            if stripped.startswith(p):
                col = line.find(word)
                return (i, col)
    return None

def lint_source(text):
    """Basic lint checks."""
    diags = []
    for i, line in enumerate(text.split("\n")):
        # Tab check
        for j, c in enumerate(line):
            if c == "\t":
                diags.append({
                    "range": lsp_range(i, j, i, j + 1),
                    "severity": 2,
                    "source": "jda",
                    "message": "use spaces, not tabs"
                })
                break
        # Trailing whitespace
        if line and line[-1] in (" ", "\t"):
            diags.append({
                "range": lsp_range(i, len(line) - 1, i, len(line)),
                "severity": 2,
                "source": "jda",
                "message": "trailing whitespace"
            })
    return diags

def format_jda(text):
    """Format Jda source with 4-space indentation."""
    lines = text.split("\n")
    out = []
    depth = 0
    for line in lines:
        stripped = line.strip()
        if not stripped:
            out.append("")
            continue
        if stripped.startswith("}"):
            depth = max(0, depth - 1)
        out.append("    " * depth + stripped)
        if stripped.endswith("{"):
            depth += 1
    return "\n".join(out)

KEYWORD_DOCS = {
    "fn": "**fn** — declare a function\n```jda\nfn name(arg: type) -> ret_type { ... }\n```",
    "let": "**let** — bind a variable\n```jda\nlet x = 42\n```",
    "mut": "**mut** — mutable variable qualifier",
    "ret": "**ret** — return a value from a function",
    "if": "**if** — conditional branch",
    "else": "**else** — alternative branch",
    "loop": "**loop** — loop construct\n```jda\nloop i < n { ... }\n```",
    "match": "**match** — exhaustive pattern matching",
    "struct": "**struct** — define a data structure",
    "enum": "**enum** — define a tagged union",
    "impl": "**impl** — implement methods for a type",
    "spawn": "**spawn** — launch a J-Thread",
    "tensor": "**tensor** — declare a native tensor",
    "defer": "**defer** — run statement at scope exit",
    "const": "**const** — compile-time constant",
    "import": "**import** — import a module",
    "syscall": "**syscall** — direct Linux syscall\n```jda\nsyscall(number, arg1, arg2, arg3)\n```",
    "print": "**print** — print a string to stdout",
    "i64": "**i64** — 64-bit signed integer type",
    "f64": "**f64** — 64-bit floating point type",
    "bool": "**bool** — boolean type (true/false)",
}

KEYWORDS = [
    "fn", "let", "mut", "ret", "if", "else", "loop", "for",
    "match", "struct", "enum", "impl", "import", "const",
    "defer", "spawn", "tensor", "own", "ref", "and", "or",
    "not", "in", "break", "continue", "true", "false",
    "syscall", "print", "i64", "f64", "bool",
]

# ─── LSP helpers ──────────────────────────────────────────────────────────────

def lsp_range(sl, sc, el, ec):
    return {
        "start": {"line": sl, "character": sc},
        "end": {"line": el, "character": ec}
    }

def extract_position(params):
    td = params.get("textDocument", {})
    uri = td.get("uri", "")
    pos = params.get("position", {})
    line = pos.get("line", 0)
    col = pos.get("character", 0)
    return uri, line, col

# ─── handlers ─────────────────────────────────────────────────────────────────

def handle_initialize(req_id, params):
    send_response(req_id, {
        "capabilities": {
            "textDocumentSync": 1,
            "hoverProvider": True,
            "completionProvider": {"triggerCharacters": [".", ":"]},
            "definitionProvider": True,
            "documentSymbolProvider": True,
            "documentFormattingProvider": True,
            "workspaceSymbolProvider": True,
        },
        "serverInfo": {"name": "jda-lsp", "version": "0.1.0"}
    })

def handle_shutdown(req_id):
    send_response(req_id, None)

def handle_did_open(params):
    td = params.get("textDocument", {})
    uri = td.get("uri", "")
    text = td.get("text", "")
    docs[uri] = text
    publish_diagnostics(uri, text)

def handle_did_change(params):
    td = params.get("textDocument", {})
    uri = td.get("uri", "")
    changes = params.get("contentChanges", [])
    if changes:
        text = changes[-1].get("text", "")
        docs[uri] = text
        publish_diagnostics(uri, text)

def handle_did_close(params):
    uri = params.get("textDocument", {}).get("uri", "")
    docs.pop(uri, None)
    send_notification("textDocument/publishDiagnostics",
                      {"uri": uri, "diagnostics": []})

def publish_diagnostics(uri, text):
    diags = lint_source(text)
    send_notification("textDocument/publishDiagnostics",
                      {"uri": uri, "diagnostics": diags})

def handle_hover(req_id, params):
    uri, line, col = extract_position(params)
    text = docs.get(uri, "")
    w = word_at(text, line, col)
    if not w:
        send_response(req_id, None)
        return

    doc = KEYWORD_DOCS.get(w, "")
    if not doc:
        # Check if it's a user-defined symbol
        for l in text.split("\n"):
            stripped = l.strip()
            if stripped.startswith(f"fn {w}("):
                sig = stripped.split("{")[0].strip()
                doc = f"**{w}**\n```jda\n{sig}\n```"
                break
            elif stripped.startswith(f"struct {w}"):
                doc = f"**struct {w}**"
                break
            elif stripped.startswith(f"enum {w}"):
                doc = f"**enum {w}**"
                break

    if doc:
        send_response(req_id, {
            "contents": {"kind": "markdown", "value": doc}
        })
    else:
        send_response(req_id, None)

def handle_completion(req_id, params):
    uri, line, col = extract_position(params)
    text = docs.get(uri, "")
    prefix = word_before(text, line, col)

    items = []
    # Keywords
    for kw in KEYWORDS:
        if kw.startswith(prefix):
            items.append({"label": kw, "kind": 14, "detail": "keyword"})

    # Symbols from document
    for sym in extract_symbols(text):
        if sym["name"].startswith(prefix):
            items.append({
                "label": sym["name"],
                "kind": sym["kind"],
                "detail": {12: "function", 23: "struct", 10: "enum",
                           14: "constant", 11: "impl"}.get(sym["kind"], "symbol")
            })

    # Variables from document
    for l in text.split("\n"):
        stripped = l.strip()
        m = re.match(r"let\s+(?:mut\s+)?([a-zA-Z_]\w*)", stripped)
        if m:
            name = m.group(1)
            if name.startswith(prefix) and not any(i["label"] == name for i in items):
                items.append({"label": name, "kind": 6, "detail": "variable"})

    send_response(req_id, items)

def handle_definition(req_id, params):
    uri, line, col = extract_position(params)
    text = docs.get(uri, "")
    w = word_at(text, line, col)
    result = find_definition(text, w)
    if result:
        dl, dc = result
        send_response(req_id, {
            "uri": uri,
            "range": lsp_range(dl, dc, dl, dc + len(w))
        })
    else:
        send_response(req_id, None)

def handle_document_symbol(req_id, params):
    uri = params.get("textDocument", {}).get("uri", "")
    text = docs.get(uri, "")
    symbols = extract_symbols(text)
    result = []
    for sym in symbols:
        result.append({
            "name": sym["name"],
            "kind": sym["kind"],
            "location": {
                "uri": uri,
                "range": lsp_range(sym["line"], sym["col"],
                                   sym["line"], sym["col"] + len(sym["name"]))
            }
        })
    send_response(req_id, result)

def handle_formatting(req_id, params):
    uri = params.get("textDocument", {}).get("uri", "")
    text = docs.get(uri, "")
    formatted = format_jda(text)
    line_count = text.count("\n") + 1
    send_response(req_id, [{
        "range": lsp_range(0, 0, line_count, 0),
        "newText": formatted
    }])

def handle_workspace_symbol(req_id, params):
    query = params.get("query", "")
    result = []
    for uri, text in docs.items():
        for sym in extract_symbols(text):
            if not query or query in sym["name"]:
                result.append({
                    "name": sym["name"],
                    "kind": sym["kind"],
                    "location": {
                        "uri": uri,
                        "range": lsp_range(sym["line"], sym["col"],
                                           sym["line"], sym["col"] + len(sym["name"]))
                    }
                })
    send_response(req_id, result)

# ─── main loop ────────────────────────────────────────────────────────────────

def main():
    log("jda-lsp starting")
    shutdown = False

    while not shutdown:
        msg = read_message()
        if msg is None:
            break

        method = msg.get("method", "")
        req_id = msg.get("id")
        params = msg.get("params", {})

        log(f"method={method} id={req_id}")

        if method == "initialize":
            handle_initialize(req_id, params)
        elif method == "initialized":
            pass
        elif method == "shutdown":
            handle_shutdown(req_id)
            shutdown = True
        elif method == "exit":
            break
        elif method == "textDocument/didOpen":
            handle_did_open(params)
        elif method == "textDocument/didChange":
            handle_did_change(params)
        elif method == "textDocument/didClose":
            handle_did_close(params)
        elif method == "textDocument/hover":
            handle_hover(req_id, params)
        elif method == "textDocument/completion":
            handle_completion(req_id, params)
        elif method == "textDocument/definition":
            handle_definition(req_id, params)
        elif method == "textDocument/documentSymbol":
            handle_document_symbol(req_id, params)
        elif method == "textDocument/formatting":
            handle_formatting(req_id, params)
        elif method == "workspace/symbol":
            handle_workspace_symbol(req_id, params)
        else:
            log(f"unhandled: {method}")
            if req_id is not None:
                send_error(req_id, -32601, f"method not found: {method}")

    log("jda-lsp exiting")

if __name__ == "__main__":
    main()
