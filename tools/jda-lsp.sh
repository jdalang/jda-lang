#!/bin/bash
# jda-lsp — Language Server Protocol server for Jda (pure bash)
#
# Implements LSP 3.17 over stdin/stdout (JSON-RPC 2.0).
# Transport: Content-Length: <n>\r\n\r\n<json>
#
# Capabilities:
#   - textDocument/didOpen, didChange, didClose
#   - textDocument/publishDiagnostics (basic syntax checks)
#   - textDocument/hover (keyword documentation)
#   - textDocument/completion (keywords + symbols in scope)
#   - textDocument/definition (go-to-definition for fn/struct/enum/const)
#   - textDocument/documentSymbol (outline view)
#   - textDocument/formatting (indent normalization)
#   - workspace/symbol
#
# Usage:
#   Invoked by editors via config: "command": ["tools/jda-lsp.sh"]

set -f  # disable globbing

LOG_FILE="${JDA_LSP_LOG:-}"

# Temporary directory for document storage (one file per URI)
DOC_DIR=$(mktemp -d)
trap 'rm -rf "$DOC_DIR"' EXIT

log() {
    if [[ -n "$LOG_FILE" ]]; then
        printf '%s\n' "$1" >> "$LOG_FILE"
    fi
}

# ─── JSON helpers (minimal, using awk) ───────────────────────────────────────

# Extract a top-level string value from JSON: json_str '{"key":"val"}' key -> val
json_str() {
    printf '%s' "$1" | awk -v key="\"$2\"" '
    BEGIN { RS=""; FS="" }
    {
        n = length($0)
        klen = length(key)
        for (i = 1; i <= n - klen + 1; i++) {
            if (substr($0, i, klen) == key) {
                j = i + klen
                while (j <= n && substr($0, j, 1) ~ /[ \t\r\n:]/) j++
                if (substr($0, j, 1) == "\"") {
                    j++
                    val = ""
                    while (j <= n) {
                        ch = substr($0, j, 1)
                        if (ch == "\\") {
                            j++
                            ech = substr($0, j, 1)
                            if (ech == "n") val = val "\n"
                            else if (ech == "t") val = val "\t"
                            else if (ech == "r") val = val "\r"
                            else if (ech == "\"") val = val "\""
                            else if (ech == "\\") val = val "\\"
                            else if (ech == "/") val = val "/"
                            else val = val ech
                        } else if (ch == "\"") {
                            break
                        } else {
                            val = val ch
                        }
                        j++
                    }
                    print val
                    exit
                }
            }
        }
    }'
}

# Extract a numeric or null value: json_num '{"id":3}' id -> 3
json_num() {
    printf '%s' "$1" | awk -v key="\"$2\"" '
    BEGIN { RS=""; FS="" }
    {
        n = length($0)
        for (i = 1; i <= n; i++) {
            klen = length(key)
            if (substr($0, i, klen) == key) {
                j = i + klen
                while (j <= n && substr($0, j, 1) ~ /[ \t\r\n:]/) j++
                val = ""
                while (j <= n && substr($0, j, 1) ~ /[-0-9.eEnull]/) {
                    val = val substr($0, j, 1)
                    j++
                }
                if (val != "") { print val; exit }
            }
        }
    }'
}

# Extract the "text" field which may contain newlines (special handling for didOpen/didChange)
json_text_field() {
    printf '%s' "$1" | awk '
    BEGIN { RS=""; FS="" }
    {
        n = length($0)
        target = "\"text\""
        tlen = length(target)
        for (i = 1; i <= n; i++) {
            if (substr($0, i, tlen) == target) {
                j = i + tlen
                while (j <= n && substr($0, j, 1) ~ /[ \t\r\n:]/) j++
                if (substr($0, j, 1) == "\"") {
                    j++
                    val = ""
                    while (j <= n) {
                        ch = substr($0, j, 1)
                        if (ch == "\\") {
                            j++
                            ech = substr($0, j, 1)
                            if (ech == "n") val = val "\n"
                            else if (ech == "t") val = val "\t"
                            else if (ech == "r") val = val "\r"
                            else if (ech == "\"") val = val "\""
                            else if (ech == "\\") val = val "\\"
                            else if (ech == "/") val = val "/"
                            else if (ech == "u") {
                                # skip \uXXXX, emit placeholder
                                j += 4; val = val "?"
                            } else val = val ech
                        } else if (ch == "\"") {
                            break
                        } else {
                            val = val ch
                        }
                        j++
                    }
                    print val
                    exit
                }
            }
        }
    }'
}

# ─── JSON encoding ───────────────────────────────────────────────────────────

json_escape() {
    # Escape a string for JSON output
    printf '%s' "$1" | awk '
    BEGIN { RS="\x01"; ORS="" }
    {
        n = length($0)
        for (i = 1; i <= n; i++) {
            c = substr($0, i, 1)
            if (c == "\\") printf "\\\\"
            else if (c == "\"") printf "\\\""
            else if (c == "\n") printf "\\n"
            else if (c == "\r") printf "\\r"
            else if (c == "\t") printf "\\t"
            else printf "%s", c
        }
    }'
}

# ─── LSP transport ───────────────────────────────────────────────────────────

send_raw() {
    local body="$1"
    local len=${#body}
    printf 'Content-Length: %d\r\n\r\n%s' "$len" "$body"
}

send_response() {
    local req_id="$1"
    local result="$2"
    local body
    if [[ "$req_id" == "null" ]] || [[ -z "$req_id" ]]; then
        body="{\"jsonrpc\":\"2.0\",\"id\":null,\"result\":$result}"
    elif [[ "$req_id" =~ ^[0-9]+$ ]]; then
        body="{\"jsonrpc\":\"2.0\",\"id\":$req_id,\"result\":$result}"
    else
        body="{\"jsonrpc\":\"2.0\",\"id\":\"$req_id\",\"result\":$result}"
    fi
    send_raw "$body"
}

send_error() {
    local req_id="$1"
    local code="$2"
    local message="$3"
    local esc_msg
    esc_msg=$(json_escape "$message")
    local body
    if [[ "$req_id" =~ ^[0-9]+$ ]]; then
        body="{\"jsonrpc\":\"2.0\",\"id\":$req_id,\"error\":{\"code\":$code,\"message\":\"$esc_msg\"}}"
    else
        body="{\"jsonrpc\":\"2.0\",\"id\":\"$req_id\",\"error\":{\"code\":$code,\"message\":\"$esc_msg\"}}"
    fi
    send_raw "$body"
}

send_notification() {
    local method="$1"
    local params="$2"
    local body="{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"params\":$params}"
    send_raw "$body"
}

# ─── Document store helpers ──────────────────────────────────────────────────

uri_to_file() {
    # Convert URI to a safe filename for temp storage
    printf '%s' "$1" | awk '{gsub(/[^a-zA-Z0-9._-]/,"_"); print}'
}

doc_store() {
    local uri="$1"
    local text="$2"
    local fname
    fname=$(uri_to_file "$uri")
    printf '%s' "$text" > "$DOC_DIR/$fname"
}

doc_load() {
    local uri="$1"
    local fname
    fname=$(uri_to_file "$uri")
    if [[ -f "$DOC_DIR/$fname" ]]; then
        cat "$DOC_DIR/$fname"
    fi
}

doc_remove() {
    local uri="$1"
    local fname
    fname=$(uri_to_file "$uri")
    rm -f "$DOC_DIR/$fname"
}

doc_list() {
    # Print all stored URIs (reconstructed from filenames isn't feasible,
    # so we store a manifest)
    if [[ -f "$DOC_DIR/_manifest" ]]; then
        cat "$DOC_DIR/_manifest"
    fi
}

manifest_add() {
    local uri="$1"
    # Add if not already present
    if ! grep -qxF "$uri" "$DOC_DIR/_manifest" 2>/dev/null; then
        printf '%s\n' "$uri" >> "$DOC_DIR/_manifest"
    fi
}

manifest_remove() {
    local uri="$1"
    if [[ -f "$DOC_DIR/_manifest" ]]; then
        grep -vxF "$uri" "$DOC_DIR/_manifest" > "$DOC_DIR/_manifest.tmp" 2>/dev/null || true
        mv "$DOC_DIR/_manifest.tmp" "$DOC_DIR/_manifest"
    fi
}

# ─── Source analysis (awk-based) ─────────────────────────────────────────────

extract_symbols() {
    # Reads text from stdin, outputs lines: name\tkind\tline\tcol
    awk '
    {
        stripped = $0; gsub(/^[ \t]+|[ \t]+$/, "", stripped)
        name = ""; kind = 0; col = 0
        if (stripped ~ /^fn[ \t]+[a-zA-Z_]/) {
            name = stripped; sub(/^fn[ \t]+/, "", name); sub(/[^a-zA-Z0-9_].*/, "", name); kind = 12
        } else if (stripped ~ /^struct[ \t]+[a-zA-Z_]/) {
            name = stripped; sub(/^struct[ \t]+/, "", name); sub(/[^a-zA-Z0-9_].*/, "", name); kind = 23
        } else if (stripped ~ /^enum[ \t]+[a-zA-Z_]/) {
            name = stripped; sub(/^enum[ \t]+/, "", name); sub(/[^a-zA-Z0-9_].*/, "", name); kind = 10
        } else if (stripped ~ /^const[ \t]+[a-zA-Z_]/) {
            name = stripped; sub(/^const[ \t]+/, "", name); sub(/[^a-zA-Z0-9_].*/, "", name); kind = 14
        } else if (stripped ~ /^impl[ \t]+[a-zA-Z_]/) {
            name = stripped; sub(/^impl[ \t]+/, "", name); sub(/[^a-zA-Z0-9_].*/, "", name); kind = 11
        }
        if (name != "" && kind > 0) {
            col = index($0, name) - 1
            if (col < 0) col = 0
            print name "\t" kind "\t" (NR-1) "\t" col
        }
    }'
}

find_definition() {
    # Args: word. Reads text from stdin. Outputs: line\tcol or nothing.
    local word="$1"
    awk -v word="$word" '
    BEGIN { found = 0 }
    {
        stripped = $0; gsub(/^[ \t]+|[ \t]+$/, "", stripped)
        if (!found) {
            pat1 = "fn " word "("
            pat2 = "struct " word " "
            pat3 = "struct " word "{"
            pat4 = "enum " word " "
            pat5 = "enum " word "{"
            pat6 = "const " word " "
            if (substr(stripped, 1, length(pat1)) == pat1 ||
                substr(stripped, 1, length(pat2)) == pat2 ||
                substr(stripped, 1, length(pat3)) == pat3 ||
                substr(stripped, 1, length(pat4)) == pat4 ||
                substr(stripped, 1, length(pat5)) == pat5 ||
                substr(stripped, 1, length(pat6)) == pat6) {
                col = index($0, word) - 1
                if (col < 0) col = 0
                print (NR-1) "\t" col
                found = 1
            }
        }
    }'
}

lint_source() {
    # Reads text from stdin, outputs JSON array of diagnostics
    awk '
    BEGIN { first = 1; printf "[" }
    {
        line = $0; lineno = NR - 1
        # Tab check
        tab_found = 0
        for (j = 1; j <= length(line); j++) {
            if (substr(line, j, 1) == "\t") {
                if (!first) printf ","
                first = 0
                printf "{\"range\":{\"start\":{\"line\":%d,\"character\":%d},\"end\":{\"line\":%d,\"character\":%d}},\"severity\":2,\"source\":\"jda\",\"message\":\"use spaces, not tabs\"}", lineno, j-1, lineno, j
                tab_found = 1
                break
            }
        }
        # Trailing whitespace
        if (length(line) > 0) {
            last = substr(line, length(line), 1)
            if (last == " " || last == "\t") {
                if (!first) printf ","
                first = 0
                printf "{\"range\":{\"start\":{\"line\":%d,\"character\":%d},\"end\":{\"line\":%d,\"character\":%d}},\"severity\":2,\"source\":\"jda\",\"message\":\"trailing whitespace\"}", lineno, length(line)-1, lineno, length(line)
            }
        }
    }
    END { printf "]" }'
}

format_jda() {
    # Reads text from stdin, outputs formatted text as JSON-escaped string
    awk '
    BEGIN { depth = 0; first = 1 }
    {
        stripped = $0; gsub(/^[ \t]+|[ \t]+$/, "", stripped)
        if (!first) result = result "\\n"
        first = 0
        if (stripped == "") {
            result = result ""
        } else {
            if (substr(stripped, 1, 1) == "}") {
                depth--
                if (depth < 0) depth = 0
            }
            indent = ""
            for (d = 0; d < depth; d++) indent = indent "    "
            # escape backslashes and quotes for JSON
            gsub(/\\/, "\\\\", stripped)
            gsub(/"/, "\\\"", stripped)
            gsub(/\t/, "\\t", stripped)
            result = result indent stripped
            if (substr(stripped, length(stripped), 1) == "{") {
                depth++
            }
        }
    }
    END { print result }'
}

word_at() {
    # Args: line_number col_number. Reads text from stdin. Outputs the word.
    local target_line="$1"
    local target_col="$2"
    awk -v tline="$target_line" -v tcol="$target_col" '
    NR == tline + 1 {
        ln = $0
        n = length(ln)
        if (tcol >= n) exit
        # expand left
        s = tcol + 1  # 1-based
        e = tcol + 1
        while (s > 1 && match(substr(ln, s-1, 1), /[a-zA-Z0-9_]/)) s--
        while (e <= n && match(substr(ln, e, 1), /[a-zA-Z0-9_]/)) e++
        if (e > s) print substr(ln, s, e - s)
    }'
}

word_before() {
    # Args: line_number col_number. Reads text from stdin. Outputs the prefix.
    local target_line="$1"
    local target_col="$2"
    awk -v tline="$target_line" -v tcol="$target_col" '
    NR == tline + 1 {
        ln = $0
        n = length(ln)
        e = tcol + 1
        if (e > n) e = n + 1
        s = e
        while (s > 1 && match(substr(ln, s-1, 1), /[a-zA-Z0-9_]/)) s--
        if (e > s) print substr(ln, s, e - s)
    }'
}

# ─── Keyword data ────────────────────────────────────────────────────────────

keyword_doc() {
    case "$1" in
        fn)     printf '**fn** \\u2014 declare a function\\n```jda\\nfn name(arg: type) -> ret_type { ... }\\n```' ;;
        let)    printf '**let** \\u2014 bind a variable\\n```jda\\nlet x = 42\\n```' ;;
        mut)    printf '**mut** \\u2014 mutable variable qualifier' ;;
        ret)    printf '**ret** \\u2014 return a value from a function' ;;
        if)     printf '**if** \\u2014 conditional branch' ;;
        else)   printf '**else** \\u2014 alternative branch' ;;
        loop)   printf '**loop** \\u2014 loop construct\\n```jda\\nloop i < n { ... }\\n```' ;;
        match)  printf '**match** \\u2014 exhaustive pattern matching' ;;
        struct) printf '**struct** \\u2014 define a data structure' ;;
        enum)   printf '**enum** \\u2014 define a tagged union' ;;
        impl)   printf '**impl** \\u2014 implement methods for a type' ;;
        spawn)  printf '**spawn** \\u2014 launch a J-Thread' ;;
        tensor) printf '**tensor** \\u2014 declare a native tensor' ;;
        defer)  printf '**defer** \\u2014 run statement at scope exit' ;;
        const)  printf '**const** \\u2014 compile-time constant' ;;
        import) printf '**import** \\u2014 import a module' ;;
        syscall) printf '**syscall** \\u2014 direct Linux syscall\\n```jda\\nsyscall(number, arg1, arg2, arg3)\\n```' ;;
        print)  printf '**print** \\u2014 print a string to stdout' ;;
        i64)    printf '**i64** \\u2014 64-bit signed integer type' ;;
        f64)    printf '**f64** \\u2014 64-bit floating point type' ;;
        bool)   printf '**bool** \\u2014 boolean type (true/false)' ;;
        *)      return 1 ;;
    esac
}

KEYWORDS="fn let mut ret if else loop for match struct enum impl import const defer spawn tensor own ref and or not in break continue true false syscall print i64 f64 bool"

# ─── Handlers ────────────────────────────────────────────────────────────────

handle_initialize() {
    local req_id="$1"
    send_response "$req_id" '{"capabilities":{"textDocumentSync":1,"hoverProvider":true,"completionProvider":{"triggerCharacters":[".",":"]},"definitionProvider":true,"documentSymbolProvider":true,"documentFormattingProvider":true,"workspaceSymbolProvider":true},"serverInfo":{"name":"jda-lsp","version":"0.1.0"}}'
}

handle_shutdown() {
    local req_id="$1"
    send_response "$req_id" "null"
}

publish_diagnostics() {
    local uri="$1"
    local text
    text=$(doc_load "$uri")
    local diags
    diags=$(printf '%s' "$text" | lint_source)
    local esc_uri
    esc_uri=$(json_escape "$uri")
    send_notification "textDocument/publishDiagnostics" "{\"uri\":\"$esc_uri\",\"diagnostics\":$diags}"
}

handle_did_open() {
    local json="$1"
    local uri
    uri=$(printf '%s' "$json" | awk '
    BEGIN { RS=""; FS="" }
    {
        n = length($0)
        # Find "textDocument" then "uri"
        td = "\"textDocument\""
        for (i = 1; i <= n; i++) {
            if (substr($0, i, length(td)) == td) {
                # Now find "uri" after this
                utgt = "\"uri\""
                for (j = i + length(td); j <= n; j++) {
                    if (substr($0, j, length(utgt)) == utgt) {
                        k = j + length(utgt)
                        while (k <= n && substr($0, k, 1) ~ /[ \t\r\n:]/) k++
                        if (substr($0, k, 1) == "\"") {
                            k++; val = ""
                            while (k <= n && substr($0, k, 1) != "\"") {
                                val = val substr($0, k, 1); k++
                            }
                            print val; exit
                        }
                    }
                }
            }
        }
    }')
    local text
    text=$(json_text_field "$json")
    doc_store "$uri" "$text"
    manifest_add "$uri"
    publish_diagnostics "$uri"
}

handle_did_change() {
    local json="$1"
    local uri
    uri=$(printf '%s' "$json" | awk '
    BEGIN { RS=""; FS="" }
    {
        n = length($0)
        td = "\"textDocument\""
        for (i = 1; i <= n; i++) {
            if (substr($0, i, length(td)) == td) {
                utgt = "\"uri\""
                for (j = i + length(td); j <= n; j++) {
                    if (substr($0, j, length(utgt)) == utgt) {
                        k = j + length(utgt)
                        while (k <= n && substr($0, k, 1) ~ /[ \t\r\n:]/) k++
                        if (substr($0, k, 1) == "\"") {
                            k++; val = ""
                            while (k <= n && substr($0, k, 1) != "\"") {
                                val = val substr($0, k, 1); k++
                            }
                            print val; exit
                        }
                    }
                }
            }
        }
    }')
    local text
    text=$(json_text_field "$json")
    if [[ -n "$text" ]]; then
        doc_store "$uri" "$text"
        publish_diagnostics "$uri"
    fi
}

handle_did_close() {
    local json="$1"
    local uri
    uri=$(json_str "$json" "uri")
    doc_remove "$uri"
    manifest_remove "$uri"
    local esc_uri
    esc_uri=$(json_escape "$uri")
    send_notification "textDocument/publishDiagnostics" "{\"uri\":\"$esc_uri\",\"diagnostics\":[]}"
}

handle_hover() {
    local req_id="$1"
    local json="$2"
    local uri line col
    uri=$(json_str "$json" "uri")
    line=$(json_num "$json" "line")
    col=$(json_num "$json" "character")
    local text
    text=$(doc_load "$uri")
    if [[ -z "$text" ]]; then
        send_response "$req_id" "null"
        return
    fi
    local w
    w=$(printf '%s' "$text" | word_at "$line" "$col")
    if [[ -z "$w" ]]; then
        send_response "$req_id" "null"
        return
    fi
    local doc
    doc=$(keyword_doc "$w")
    if [[ -z "$doc" ]]; then
        # Check user-defined symbols
        doc=$(printf '%s' "$text" | awk -v word="$w" '
        {
            stripped = $0; gsub(/^[ \t]+|[ \t]+$/, "", stripped)
            pat = "fn " word "("
            if (substr(stripped, 1, length(pat)) == pat) {
                sig = stripped
                idx = index(sig, "{")
                if (idx > 0) sig = substr(sig, 1, idx - 1)
                gsub(/[ \t]+$/, "", sig)
                gsub(/\\/, "\\\\", sig)
                gsub(/"/, "\\\"", sig)
                printf "**%s**\\n```jda\\n%s\\n```", word, sig
                exit
            }
            pat2 = "struct " word
            if (substr(stripped, 1, length(pat2)) == pat2) {
                ch = substr(stripped, length(pat2)+1, 1)
                if (ch == " " || ch == "{" || ch == "") {
                    printf "**struct %s**", word; exit
                }
            }
            pat3 = "enum " word
            if (substr(stripped, 1, length(pat3)) == pat3) {
                ch = substr(stripped, length(pat3)+1, 1)
                if (ch == " " || ch == "{" || ch == "") {
                    printf "**enum %s**", word; exit
                }
            }
        }')
    fi
    if [[ -n "$doc" ]]; then
        send_response "$req_id" "{\"contents\":{\"kind\":\"markdown\",\"value\":\"$doc\"}}"
    else
        send_response "$req_id" "null"
    fi
}

handle_completion() {
    local req_id="$1"
    local json="$2"
    local uri line col
    uri=$(json_str "$json" "uri")
    line=$(json_num "$json" "line")
    col=$(json_num "$json" "character")
    local text
    text=$(doc_load "$uri")
    local prefix
    prefix=$(printf '%s' "$text" | word_before "$line" "$col")

    local items
    items=$(
        {
            # Keywords
            for kw in $KEYWORDS; do
                if [[ -z "$prefix" ]] || [[ "$kw" == "$prefix"* ]]; then
                    printf 'KW\t%s\n' "$kw"
                fi
            done
            # Symbols from document
            if [[ -n "$text" ]]; then
                printf '%s' "$text" | extract_symbols | while IFS=$'\t' read -r name kind sline scol; do
                    if [[ -z "$prefix" ]] || [[ "$name" == "$prefix"* ]]; then
                        printf 'SYM\t%s\t%s\n' "$name" "$kind"
                    fi
                done
            fi
            # Variables
            if [[ -n "$text" ]]; then
                printf '%s' "$text" | awk -v prefix="$prefix" '
                {
                    stripped = $0; gsub(/^[ \t]+|[ \t]+$/, "", stripped)
                    if (stripped ~ /^let[ \t]/) {
                        name = stripped; sub(/^let[ \t]+(mut[ \t]+)?/, "", name); sub(/[^a-zA-Z0-9_].*/, "", name)
                        if (prefix == "" || substr(name, 1, length(prefix)) == prefix) {
                            print "VAR\t" name
                        }
                    }
                }'
            fi
        } | awk '
        BEGIN { first = 1; printf "[" }
        {
            split($0, f, "\t")
            type = f[1]; name = f[2]
            # Dedup
            if (name in seen) next
            seen[name] = 1
            if (!first) printf ","
            first = 0
            if (type == "KW") {
                printf "{\"label\":\"%s\",\"kind\":14,\"detail\":\"keyword\"}", name
            } else if (type == "SYM") {
                skind = f[3] + 0
                detail = "symbol"
                if (skind == 12) detail = "function"
                else if (skind == 23) detail = "struct"
                else if (skind == 10) detail = "enum"
                else if (skind == 14) detail = "constant"
                else if (skind == 11) detail = "impl"
                printf "{\"label\":\"%s\",\"kind\":%d,\"detail\":\"%s\"}", name, skind, detail
            } else if (type == "VAR") {
                printf "{\"label\":\"%s\",\"kind\":6,\"detail\":\"variable\"}", name
            }
        }
        END { printf "]" }'
    )
    send_response "$req_id" "$items"
}

handle_definition() {
    local req_id="$1"
    local json="$2"
    local uri line col
    uri=$(json_str "$json" "uri")
    line=$(json_num "$json" "line")
    col=$(json_num "$json" "character")
    local text
    text=$(doc_load "$uri")
    local w
    w=$(printf '%s' "$text" | word_at "$line" "$col")
    if [[ -z "$w" ]]; then
        send_response "$req_id" "null"
        return
    fi
    local def
    def=$(printf '%s' "$text" | find_definition "$w")
    if [[ -n "$def" ]]; then
        local dl dc
        dl=$(printf '%s' "$def" | cut -f1)
        dc=$(printf '%s' "$def" | cut -f2)
        local wlen=${#w}
        local esc_uri
        esc_uri=$(json_escape "$uri")
        send_response "$req_id" "{\"uri\":\"$esc_uri\",\"range\":{\"start\":{\"line\":$dl,\"character\":$dc},\"end\":{\"line\":$dl,\"character\":$((dc + wlen))}}}"
    else
        send_response "$req_id" "null"
    fi
}

handle_document_symbol() {
    local req_id="$1"
    local json="$2"
    local uri
    uri=$(json_str "$json" "uri")
    local text
    text=$(doc_load "$uri")
    local esc_uri
    esc_uri=$(json_escape "$uri")
    local result
    result=$(printf '%s' "$text" | extract_symbols | awk -v uri="$esc_uri" '
    BEGIN { first = 1; printf "["; FS="\t" }
    {
        name = $1; kind = $2; sline = $3; scol = $4
        nlen = length(name)
        if (!first) printf ","
        first = 0
        printf "{\"name\":\"%s\",\"kind\":%d,\"location\":{\"uri\":\"%s\",\"range\":{\"start\":{\"line\":%d,\"character\":%d},\"end\":{\"line\":%d,\"character\":%d}}}}", name, kind, uri, sline, scol, sline, scol + nlen
    }
    END { printf "]" }')
    send_response "$req_id" "$result"
}

handle_formatting() {
    local req_id="$1"
    local json="$2"
    local uri
    uri=$(json_str "$json" "uri")
    local text
    text=$(doc_load "$uri")
    local line_count
    line_count=$(printf '%s' "$text" | awk 'END { print NR }')
    [[ -z "$line_count" ]] && line_count=0
    local formatted
    formatted=$(printf '%s' "$text" | format_jda)
    send_response "$req_id" "[{\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":$line_count,\"character\":0}},\"newText\":\"$formatted\"}]"
}

handle_workspace_symbol() {
    local req_id="$1"
    local json="$2"
    local query
    query=$(json_str "$json" "query")
    local result="["
    local first=1
    while IFS= read -r uri; do
        [[ -z "$uri" ]] && continue
        local text
        text=$(doc_load "$uri")
        local esc_uri
        esc_uri=$(json_escape "$uri")
        local syms
        syms=$(printf '%s' "$text" | extract_symbols)
        while IFS=$'\t' read -r name kind sline scol; do
            [[ -z "$name" ]] && continue
            if [[ -z "$query" ]] || [[ "$name" == *"$query"* ]]; then
                local nlen=${#name}
                if [[ $first -eq 0 ]]; then
                    result="$result,"
                fi
                first=0
                result="$result{\"name\":\"$name\",\"kind\":$kind,\"location\":{\"uri\":\"$esc_uri\",\"range\":{\"start\":{\"line\":$sline,\"character\":$scol},\"end\":{\"line\":$sline,\"character\":$((scol + nlen))}}}}"
            fi
        done <<< "$syms"
    done < <(doc_list)
    result="$result]"
    send_response "$req_id" "$result"
}

# ─── Main loop ───────────────────────────────────────────────────────────────

main() {
    log "jda-lsp starting (bash)"
    local shutdown=0

    # Create a FIFO for sending messages from awk reader to bash
    local msg_fifo="$DOC_DIR/_messages"
    mkfifo "$msg_fifo"

    # Start awk-based LSP message reader in background
    # It reads Content-Length framed messages from stdin and writes them
    # NUL-terminated to the FIFO
    awk '
    BEGIN {
        RS = "\r\n"
        content_length = 0
    }
    {
        line = $0
        if (line ~ /^Content-Length:/) {
            sub(/^Content-Length:[ \t]*/, "", line)
            content_length = line + 0
        } else if (line == "" && content_length > 0) {
            # End of headers, read body
            body = ""
            remaining = content_length
            while (remaining > 0) {
                ch = ""
                for (i = 0; i < remaining; i++) {
                    if ((getline ch < "/dev/stdin") <= 0) {
                        # Try reading character by character
                        break
                    }
                    body = body ch "\n"
                    remaining = remaining - length(ch) - 1
                }
                if (remaining > 0) break
            }
            # Output as length-prefixed message
            printf "%d\n%s\n", content_length, body
            content_length = 0
        }
    }' < /dev/stdin > "$msg_fifo" &
    local reader_pid=$!

    # Actually the awk RS approach won't work well for binary body reading.
    # Kill it and use a different approach.
    kill $reader_pid 2>/dev/null
    wait $reader_pid 2>/dev/null
    rm -f "$msg_fifo"

    # Use perl as a thin message reader if available, otherwise dd
    # Perl is available on all macOS systems
    local perl_reader
    perl_reader=$(cat <<'PERL_EOF'
use strict;
use warnings;
$| = 1;
while (1) {
    my $headers = "";
    my $content_length = 0;
    while (my $line = <STDIN>) {
        $line =~ s/\r?\n$//;
        last if $line eq "";
        if ($line =~ /^Content-Length:\s*(\d+)/) {
            $content_length = $1;
        }
    }
    last if $content_length == 0;
    my $body;
    my $nread = read(STDIN, $body, $content_length);
    last if !$nread;
    # Output: length on one line, then body bytes, then NUL
    print "$content_length\n$body\0";
}
PERL_EOF
    )

    # Create a message FIFO
    mkfifo "$msg_fifo"

    # Run perl reader in background: reads LSP frames, outputs NUL-delimited bodies
    perl -e "$perl_reader" < /dev/stdin > "$msg_fifo" &
    local reader_pid=$!

    # Read messages from the FIFO
    while [[ $shutdown -eq 0 ]]; do
        local content_length_line=""
        local body=""

        # Read the length line
        if ! IFS= read -r content_length_line < "$msg_fifo" 2>/dev/null; then
            break
        fi
        # Read until NUL
        if ! IFS= read -r -d '' body < "$msg_fifo" 2>/dev/null; then
            # May have got partial read; check if we got something
            if [[ -z "$body" ]]; then
                break
            fi
        fi

        # Parse method and id
        local method
        method=$(json_str "$body" "method")
        local req_id
        req_id=$(json_num "$body" "id")

        log "method=$method id=$req_id"

        case "$method" in
            initialize)
                handle_initialize "$req_id"
                ;;
            initialized)
                # no-op
                ;;
            shutdown)
                handle_shutdown "$req_id"
                shutdown=1
                ;;
            exit)
                break
                ;;
            textDocument/didOpen)
                handle_did_open "$body"
                ;;
            textDocument/didChange)
                handle_did_change "$body"
                ;;
            textDocument/didClose)
                handle_did_close "$body"
                ;;
            textDocument/hover)
                handle_hover "$req_id" "$body"
                ;;
            textDocument/completion)
                handle_completion "$req_id" "$body"
                ;;
            textDocument/definition)
                handle_definition "$req_id" "$body"
                ;;
            textDocument/documentSymbol)
                handle_document_symbol "$req_id" "$body"
                ;;
            textDocument/formatting)
                handle_formatting "$req_id" "$body"
                ;;
            workspace/symbol)
                handle_workspace_symbol "$req_id" "$body"
                ;;
            *)
                log "unhandled: $method"
                if [[ -n "$req_id" ]] && [[ "$req_id" != "null" ]]; then
                    send_error "$req_id" -32601 "method not found: $method"
                fi
                ;;
        esac
    done

    log "jda-lsp exiting"
}

main
