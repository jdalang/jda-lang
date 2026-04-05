#!/bin/bash
set -euo pipefail
#
# jda-wasm — WebAssembly compiler for Jda source files (pure bash + awk)
#
# Compiles Jda source to WebAssembly binary (.wasm) format.
# Supports WASI target for CLI programs and browser target for web.
#
# Usage:
#   jda-wasm.sh <file.jda>                    Compile to .wasm (WASI target)
#   jda-wasm.sh --target browser <file.jda>   Compile for browser (no WASI)
#   jda-wasm.sh --wat <file.jda>              Output WAT (text format) only
#   jda-wasm.sh --run <file.jda>              Compile and run with wasmtime/node
#   jda-wasm.sh --html <file.jda>             Generate HTML playground page
#   jda-wasm.sh -o <output> <file.jda>        Specify output file name

# ─── CLI Argument Parsing ───────────────────────────────────────────────────

TARGET="wasi"
WAT_ONLY=0
DO_RUN=0
DO_HTML=0
OUTPUT=""
SOURCE=""

if [[ $# -eq 0 ]]; then
    echo "jda-wasm — WebAssembly compiler for Jda"
    echo ""
    echo "Usage:"
    echo "  jda-wasm.sh <file.jda>                    Compile to .wasm (WASI)"
    echo "  jda-wasm.sh --target browser <file.jda>   Browser target"
    echo "  jda-wasm.sh --wat <file.jda>              Output WAT text format"
    echo "  jda-wasm.sh --run <file.jda>              Compile and run"
    echo "  jda-wasm.sh --html <file.jda>             Generate playground HTML"
    echo "  jda-wasm.sh -o <output> <file.jda>        Specify output name"
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            TARGET="$2"; shift 2 ;;
        --wat)
            WAT_ONLY=1; shift ;;
        --run)
            DO_RUN=1; shift ;;
        --html)
            DO_HTML=1; TARGET="browser"; shift ;;
        -o)
            OUTPUT="$2"; shift 2 ;;
        *)
            SOURCE="$1"; shift ;;
    esac
done

if [[ -z "$SOURCE" ]]; then
    echo "error: no source file specified" >&2
    exit 1
fi

if [[ ! -f "$SOURCE" ]]; then
    echo "error: file not found: $SOURCE" >&2
    exit 1
fi

BASENAME="$(basename "${SOURCE}" .jda)"

# ─── AWK: Lexer + Parser + WAT Generator ───────────────────────────────────
#
# The entire compiler front-end (lex, parse, codegen to WAT) is a single
# awk program that reads the .jda source on stdin and writes WAT to stdout.

generate_wat() {
    awk -v target="$TARGET" '
# ─── Helper functions ───────────────────────────────────────────────────────

function die(msg) {
    print "error: " msg > "/dev/stderr"
    exit 1
}

# ─── Lexer ──────────────────────────────────────────────────────────────────

function lex(    src, n, i, c, c2, j, word, numstr) {
    src = source
    n = length(src)
    i = 1
    tok_count = 0
    line_no = 1

    while (i <= n) {
        c = substr(src, i, 1)

        # Newlines
        if (c == "\n") {
            line_no++; i++; continue
        }
        # Whitespace
        if (c == " " || c == "\t" || c == "\r") {
            i++; continue
        }
        # Comment: ;;
        if (c == ";" && i+1 <= n && substr(src, i+1, 1) == ";") {
            while (i <= n && substr(src, i, 1) != "\n") i++
            continue
        }
        # String literal
        if (c == "\"") {
            j = i + 1
            while (j <= n && substr(src, j, 1) != "\"") {
                if (substr(src, j, 1) == "\\") j++
                j++
            }
            tok_count++
            tok_kind[tok_count] = "str"
            tok_val[tok_count] = substr(src, i+1, j-i-1)
            tok_line[tok_count] = line_no
            i = j + 1
            continue
        }
        # Integer literal
        if (c ~ /[0-9]/) {
            j = i
            while (j <= n && substr(src, j, 1) ~ /[0-9]/) j++
            numstr = substr(src, i, j-i)
            tok_count++
            tok_kind[tok_count] = "int"
            tok_val[tok_count] = numstr + 0
            tok_line[tok_count] = line_no
            i = j
            continue
        }
        # Identifier or keyword
        if (c ~ /[a-zA-Z_]/) {
            j = i
            while (j <= n && substr(src, j, 1) ~ /[a-zA-Z0-9_]/) j++
            word = substr(src, i, j-i)
            tok_count++
            if (word == "fn" || word == "let" || word == "ret" || word == "if" || \
                word == "else" || word == "loop" || word == "break" || word == "print" || \
                word == "struct" || word == "enum" || word == "const" || word == "impl" || \
                word == "syscall" || word == "true" || word == "false") {
                tok_kind[tok_count] = "kw"
            } else {
                tok_kind[tok_count] = "id"
            }
            tok_val[tok_count] = word
            tok_line[tok_count] = line_no
            i = j
            continue
        }
        # Two-char operators
        if (i+1 <= n) {
            c2 = substr(src, i, 2)
            if (c2 == "->") {
                tok_count++; tok_kind[tok_count] = "->"; tok_val[tok_count] = "->"; tok_line[tok_count] = line_no; i += 2; continue
            }
            if (c2 == "==" || c2 == "!=" || c2 == "<=" || c2 == ">=") {
                tok_count++; tok_kind[tok_count] = c2; tok_val[tok_count] = c2; tok_line[tok_count] = line_no; i += 2; continue
            }
        }
        # Single-char tokens
        if (c == "(" || c == ")" || c == "{" || c == "}" || c == "," || c == ";" || c == ":") {
            tok_count++; tok_kind[tok_count] = c; tok_val[tok_count] = c; tok_line[tok_count] = line_no; i++; continue
        }
        if (c == "+" || c == "-" || c == "*" || c == "/" || c == "%" || c == "<" || c == ">" || c == "=" || c == "!") {
            tok_count++; tok_kind[tok_count] = c; tok_val[tok_count] = c; tok_line[tok_count] = line_no; i++; continue
        }
        # Skip unknown
        i++
    }
    # EOF token
    tok_count++
    tok_kind[tok_count] = "eof"
    tok_val[tok_count] = ""
    tok_line[tok_count] = line_no
}

# ─── Parser helpers ─────────────────────────────────────────────────────────

function peek_kind() { return tok_kind[pos] }
function peek_val()  { return tok_val[pos] }

function advance(    k, v) {
    k = tok_kind[pos]; v = tok_val[pos]; pos++; return v
}

function expect(k,    tk, tv) {
    tk = tok_kind[pos]; tv = tok_val[pos]
    if (tk != k) die("expected " k ", got " tk " (" tv ") line " tok_line[pos])
    pos++
    return tv
}

function expect_kw(w,    tk, tv) {
    tk = tok_kind[pos]; tv = tok_val[pos]
    if (tk != "kw" || tv != w) die("expected keyword " w " line " tok_line[pos])
    pos++
    return tv
}

# ─── AST storage ────────────────────────────────────────────────────────────
# We use a flat indexed "heap" for AST nodes. Each node has:
#   node_kind[id], node_ival[id], node_sval[id], node_name[id], node_op[id]
#   node_left[id], node_right[id], node_cond[id], node_expr[id]
#   node_child_start[id], node_child_count[id]  (for body/else_body/args/params)
#   node_else_start[id], node_else_count[id]
#   node_param_start[id], node_param_count[id]

function new_node(kind,    id) {
    id = ++node_count
    node_kind[id] = kind
    return id
}

# Children are stored in child_list[] with ranges
# child_list[idx] = node_id

function begin_list() { return child_top + 1 }

function push_child(nid) {
    child_top++
    child_list[child_top] = nid
}

# ─── Parser: expressions ───────────────────────────────────────────────────

function parse_expr() { return parse_comparison() }

function parse_comparison(    left, op, right) {
    left = parse_additive()
    while (peek_kind() == "==" || peek_kind() == "!=" || peek_kind() == "<" || \
           peek_kind() == ">" || peek_kind() == "<=" || peek_kind() == ">=") {
        op = advance()
        right = parse_additive()
        _nid = new_node("binop")
        node_op[_nid] = op
        node_left[_nid] = left
        node_right[_nid] = right
        left = _nid
    }
    return left
}

function parse_additive(    left, op, right) {
    left = parse_multiplicative()
    while (peek_kind() == "+" || peek_kind() == "-") {
        op = advance()
        right = parse_multiplicative()
        _nid = new_node("binop")
        node_op[_nid] = op
        node_left[_nid] = left
        node_right[_nid] = right
        left = _nid
    }
    return left
}

function parse_multiplicative(    left, op, right) {
    left = parse_unary()
    while (peek_kind() == "*" || peek_kind() == "/" || peek_kind() == "%") {
        op = advance()
        right = parse_unary()
        _nid = new_node("binop")
        node_op[_nid] = op
        node_left[_nid] = left
        node_right[_nid] = right
        left = _nid
    }
    return left
}

function parse_unary(    expr, zero_id) {
    if (peek_kind() == "-") {
        advance()
        expr = parse_primary()
        zero_id = new_node("int"); node_ival[zero_id] = 0
        _nid = new_node("binop"); node_op[_nid] = "-"
        node_left[_nid] = zero_id; node_right[_nid] = expr
        return _nid
    }
    return parse_primary()
}

function parse_primary(    tk, tv, nid, name, start, cnt, arg) {
    tk = peek_kind(); tv = peek_val()

    if (tk == "int") {
        advance(); nid = new_node("int"); node_ival[nid] = tv + 0; return nid
    }
    if (tk == "str") {
        advance(); nid = new_node("str"); node_sval[nid] = tv; return nid
    }
    if (tk == "kw" && tv == "true") {
        advance(); nid = new_node("int"); node_ival[nid] = 1; return nid
    }
    if (tk == "kw" && tv == "false") {
        advance(); nid = new_node("int"); node_ival[nid] = 0; return nid
    }
    if (tk == "kw" && tv == "syscall") {
        advance(); expect("(")
        nid = new_node("syscall")
        start = begin_list(); cnt = 0
        arg = parse_expr(); push_child(arg); cnt++
        while (peek_kind() == ",") { advance(); arg = parse_expr(); push_child(arg); cnt++ }
        expect(")")
        node_child_start[nid] = start; node_child_count[nid] = cnt
        return nid
    }
    if (tk == "id" || (tk == "kw" && tv != "fn" && tv != "let" && tv != "ret" && \
        tv != "if" && tv != "else" && tv != "loop" && tv != "break" && tv != "print" && \
        tv != "struct" && tv != "enum" && tv != "const" && tv != "impl")) {
        name = advance()
        if (peek_kind() == "(") {
            advance()
            nid = new_node("call"); node_name[nid] = name
            start = begin_list(); cnt = 0
            if (peek_kind() != ")") {
                arg = parse_expr(); push_child(arg); cnt++
                while (peek_kind() == ",") { advance(); arg = parse_expr(); push_child(arg); cnt++ }
            }
            expect(")")
            node_child_start[nid] = start; node_child_count[nid] = cnt
            return nid
        }
        nid = new_node("var"); node_name[nid] = name; return nid
    }
    if (tk == "(") {
        advance(); nid = parse_expr(); expect(")"); return nid
    }
    die("unexpected " tk " (" tv ") line " tok_line[pos])
}

# ─── Parser: statements ────────────────────────────────────────────────────

function parse_stmt(    tk, tv, nid, name, cond, start, cnt, s, expr, val) {
    tk = peek_kind(); tv = peek_val()

    if (tk == "kw" && tv == "let") {
        advance(); name = expect("id"); expect("=")
        nid = new_node("let"); node_name[nid] = name; node_expr[nid] = parse_expr()
        return nid
    }
    if (tk == "kw" && tv == "ret") {
        advance(); nid = new_node("ret"); node_expr[nid] = parse_expr(); return nid
    }
    if (tk == "kw" && tv == "if") {
        advance(); cond = parse_expr(); expect("{")
        nid = new_node("if"); node_cond[nid] = cond
        start = begin_list(); cnt = 0
        while (peek_kind() != "}") { s = parse_stmt(); push_child(s); cnt++ }
        expect("}")
        node_child_start[nid] = start; node_child_count[nid] = cnt
        # else?
        node_else_start[nid] = 0; node_else_count[nid] = 0
        if (peek_kind() == "kw" && peek_val() == "else") {
            advance(); expect("{")
            start = begin_list(); cnt = 0
            while (peek_kind() != "}") { s = parse_stmt(); push_child(s); cnt++ }
            expect("}")
            node_else_start[nid] = start; node_else_count[nid] = cnt
        }
        return nid
    }
    if (tk == "kw" && tv == "loop") {
        advance(); cond = parse_expr(); expect("{")
        nid = new_node("loop"); node_cond[nid] = cond
        start = begin_list(); cnt = 0
        while (peek_kind() != "}") { s = parse_stmt(); push_child(s); cnt++ }
        expect("}")
        node_child_start[nid] = start; node_child_count[nid] = cnt
        return nid
    }
    if (tk == "kw" && tv == "break") {
        advance(); return new_node("break")
    }
    if (tk == "kw" && tv == "print") {
        advance(); nid = new_node("print"); node_expr[nid] = parse_expr(); return nid
    }
    # expression statement or assignment
    expr = parse_expr()
    if (peek_kind() == "=") {
        advance(); val = parse_expr()
        nid = new_node("assign"); node_name[nid] = node_name[expr]; node_expr[nid] = val
        return nid
    }
    nid = new_node("exprstmt"); node_expr[nid] = expr
    return nid
}

# ─── Parser: functions and top-level ────────────────────────────────────────

function parse_fn(    nid, name, pstart, pcnt, pname, bstart, bcnt, s) {
    expect_kw("fn"); name = expect("id"); expect("(")
    nid = new_node("fn"); node_name[nid] = name

    # params
    pstart = begin_list(); pcnt = 0
    if (peek_kind() != ")") {
        pname = expect("id"); expect(":")
        while (peek_kind() != "," && peek_kind() != ")") advance()
        push_child(0); param_names[pstart] = pname; pcnt++
        while (peek_kind() == ",") {
            advance(); pname = expect("id"); expect(":")
            while (peek_kind() != "," && peek_kind() != ")") advance()
            push_child(0); param_names[pstart + pcnt] = pname; pcnt++
        }
    }
    expect(")")
    node_param_start[nid] = pstart; node_param_count[nid] = pcnt

    # return type (skip)
    if (peek_kind() == "->") {
        advance()
        while (peek_kind() != "{") advance()
    }

    expect("{")
    bstart = begin_list(); bcnt = 0
    while (peek_kind() != "}") { s = parse_stmt(); push_child(s); bcnt++ }
    expect("}")
    node_child_start[nid] = bstart; node_child_count[nid] = bcnt
    return nid
}

function parse_program(    fcnt, fid) {
    fcnt = 0
    while (peek_kind() != "eof") {
        if (peek_kind() == "kw" && peek_val() == "fn") {
            fid = parse_fn()
            fn_ids[fcnt] = fid
            fcnt++
        } else {
            advance()
        }
    }
    fn_list_count = fcnt
}

# ─── String collection ─────────────────────────────────────────────────────

function process_escape(s,    out, i, c, n) {
    out = ""; n = length(s); i = 1
    while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\\" && i+1 <= n) {
            c = substr(s, i+1, 1)
            if (c == "n") { out = out "\n"; i += 2; continue }
            if (c == "t") { out = out "\t"; i += 2; continue }
            if (c == "\\") { out = out "\\"; i += 2; continue }
            if (c == "\"") { out = out "\""; i += 2; continue }
            out = out "\\" c; i += 2; continue
        }
        out = out c; i++
    }
    return out
}

function add_string(s,    data, k, off) {
    data = process_escape(s)
    # Check duplicate
    for (k = 0; k < str_count; k++) {
        if (str_data[k] == data) return str_off[k]
    }
    off = data_offset
    str_off[str_count] = off
    str_data[str_count] = data
    str_len[str_count] = length(data)
    str_count++
    data_offset += length(data) + 8
    return off
}

function get_string_off(s,    data, k) {
    data = process_escape(s)
    for (k = 0; k < str_count; k++) {
        if (str_data[k] == data) return str_off[k]
    }
    return 0
}

function get_string_len(s,    data, k) {
    data = process_escape(s)
    for (k = 0; k < str_count; k++) {
        if (str_data[k] == data) return str_len[k]
    }
    return 0
}

function scan_stmts_for_strings(start, count,    i, sid, eid) {
    for (i = 0; i < count; i++) {
        sid = child_list[start + i]
        if (node_kind[sid] == "print" && node_kind[node_expr[sid]] == "str") {
            add_string(node_sval[node_expr[sid]])
        }
        if (node_child_count[sid] > 0) {
            scan_stmts_for_strings(node_child_start[sid], node_child_count[sid])
        }
        if (node_else_count[sid] > 0) {
            scan_stmts_for_strings(node_else_start[sid], node_else_count[sid])
        }
    }
}

function collect_strings(    fi, fid) {
    for (fi = 0; fi < fn_list_count; fi++) {
        fid = fn_ids[fi]
        scan_stmts_for_strings(node_child_start[fid], node_child_count[fid])
    }
}

# ─── Count locals (let bindings) ────────────────────────────────────────────

function count_locals(start, count,    i, sid, n) {
    n = 0
    for (i = 0; i < count; i++) {
        sid = child_list[start + i]
        if (node_kind[sid] == "let") n++
        if (node_child_count[sid] > 0) n += count_locals(node_child_start[sid], node_child_count[sid])
        if (node_else_count[sid] > 0)  n += count_locals(node_else_start[sid], node_else_count[sid])
    }
    return n
}

# ─── Assign local indices ──────────────────────────────────────────────────
# Uses global _lcounter to track next index

function assign_locals(start, count,    i, sid) {
    for (i = 0; i < count; i++) {
        sid = child_list[start + i]
        if (node_kind[sid] == "let") {
            locals_map[node_name[sid]] = _lcounter
            _lcounter++
        }
        if (node_child_count[sid] > 0) assign_locals(node_child_start[sid], node_child_count[sid])
        if (node_else_count[sid] > 0)  assign_locals(node_else_start[sid], node_else_count[sid])
    }
}

# ─── WAT Code Generation ───────────────────────────────────────────────────

function emit(s) { print s }

function gen_expr(nid,    k, idx, op, wop, ai, argid) {
    k = node_kind[nid]

    if (k == "int") {
        emit("    i64.const " node_ival[nid]); return
    }
    if (k == "var") {
        idx = locals_map[node_name[nid]]
        emit("    local.get " idx); return
    }
    if (k == "str") {
        emit("    i64.const " get_string_off(node_sval[nid])); return
    }
    if (k == "binop") {
        gen_expr(node_left[nid])
        gen_expr(node_right[nid])
        op = node_op[nid]
        if      (op == "+")  wop = "i64.add"
        else if (op == "-")  wop = "i64.sub"
        else if (op == "*")  wop = "i64.mul"
        else if (op == "/")  wop = "i64.div_s"
        else if (op == "%")  wop = "i64.rem_s"
        else if (op == "==") wop = "i64.eq"
        else if (op == "!=") wop = "i64.ne"
        else if (op == "<")  wop = "i64.lt_s"
        else if (op == ">")  wop = "i64.gt_s"
        else if (op == "<=") wop = "i64.le_s"
        else if (op == ">=") wop = "i64.ge_s"
        else wop = ""
        if (wop != "") emit("    " wop)
        if (op == "==" || op == "!=" || op == "<" || op == ">" || op == "<=" || op == ">=") {
            emit("    i64.extend_i32_s")
        }
        return
    }
    if (k == "call") {
        for (ai = 0; ai < node_child_count[nid]; ai++) {
            argid = child_list[node_child_start[nid] + ai]
            gen_expr(argid)
        }
        emit("    call $" node_name[nid]); return
    }
    if (k == "syscall") {
        for (ai = 0; ai < node_child_count[nid]; ai++) {
            argid = child_list[node_child_start[nid] + ai]
            gen_expr(argid)
        }
        emit("    ;; syscall (not supported in wasm, drop args)")
        for (ai = 0; ai < node_child_count[nid]; ai++) emit("    drop")
        emit("    i64.const 0")
        return
    }
}

function gen_stmt(nid,    k, idx, off, slen, si, sid) {
    k = node_kind[nid]

    if (k == "let") {
        gen_expr(node_expr[nid])
        idx = locals_map[node_name[nid]]
        emit("    local.set " idx); return
    }
    if (k == "assign") {
        gen_expr(node_expr[nid])
        idx = locals_map[node_name[nid]]
        emit("    local.set " idx); return
    }
    if (k == "ret") {
        gen_expr(node_expr[nid])
        emit("    return"); return
    }
    if (k == "if") {
        gen_expr(node_cond[nid])
        emit("    i64.const 0")
        emit("    i64.ne")
        if (node_else_count[nid] > 0) {
            emit("    if (result i64)")
            for (si = 0; si < node_child_count[nid]; si++) {
                sid = child_list[node_child_start[nid] + si]
                gen_stmt(sid)
            }
            emit("    i64.const 0")
            emit("    else")
            for (si = 0; si < node_else_count[nid]; si++) {
                sid = child_list[node_else_start[nid] + si]
                gen_stmt(sid)
            }
            emit("    i64.const 0")
            emit("    end")
            emit("    drop")
        } else {
            emit("    if")
            for (si = 0; si < node_child_count[nid]; si++) {
                sid = child_list[node_child_start[nid] + si]
                gen_stmt(sid)
            }
            emit("    end")
        }
        return
    }
    if (k == "loop") {
        emit("    block $brk")
        emit("    loop $top")
        gen_expr(node_cond[nid])
        emit("    i64.eqz")
        emit("    br_if $brk")
        for (si = 0; si < node_child_count[nid]; si++) {
            sid = child_list[node_child_start[nid] + si]
            gen_stmt(sid)
        }
        emit("    br $top")
        emit("    end")
        emit("    end")
        return
    }
    if (k == "break") {
        emit("    br $brk"); return
    }
    if (k == "print") {
        if (node_kind[node_expr[nid]] == "str") {
            off = get_string_off(node_sval[node_expr[nid]])
            slen = get_string_len(node_sval[node_expr[nid]])
            if (target == "wasi") {
                emit("    ;; print string")
                emit("    i32.const 0")
                emit("    i32.const " off)
                emit("    i32.store")
                emit("    i32.const 4")
                emit("    i32.const " slen)
                emit("    i32.store")
                emit("    i32.const 1")
                emit("    i32.const 0")
                emit("    i32.const 1")
                emit("    i32.const 8")
                emit("    call $fd_write")
                emit("    drop")
            } else {
                emit("    i32.const " off)
                emit("    i32.const " slen)
                emit("    call $print_str")
            }
        }
        return
    }
    if (k == "exprstmt") {
        gen_expr(node_expr[nid])
        emit("    drop"); return
    }
}

function gen_function(fid,    fname, pcnt, pstart, extra, pi, pstr, lstr, si, sid) {
    fname = node_name[fid]
    pcnt = node_param_count[fid]
    pstart = node_param_start[fid]

    # Build locals_map: first params, then let-bindings
    delete locals_map
    for (pi = 0; pi < pcnt; pi++) {
        locals_map[param_names[pstart + pi]] = pi
    }
    _lcounter = pcnt
    assign_locals(node_child_start[fid], node_child_count[fid])
    extra = _lcounter - pcnt

    pstr = ""
    for (pi = 0; pi < pcnt; pi++) pstr = pstr " (param i64)"
    lstr = ""
    for (pi = 0; pi < extra; pi++) lstr = lstr " (local i64)"

    emit("  (func $" fname pstr " (result i64)" lstr)

    for (si = 0; si < node_child_count[fid]; si++) {
        sid = child_list[node_child_start[fid] + si]
        gen_stmt(sid)
    }

    emit("    i64.const 0")
    emit("  )")
}

function gen_data_segments(    k, data, di, c, hex, byte_val) {
    for (k = 0; k < str_count; k++) {
        data = str_data[k]
        hex = ""
        for (di = 1; di <= length(data); di++) {
            c = substr(data, di, 1)
            byte_val = ord(c)
            hex = hex sprintf("\\%02x", byte_val)
        }
        emit("  (data (i32.const " str_off[k] ") \"" hex "\")")
    }
}

function generate_wat(    fi, fid, has_main) {
    emit("(module")

    if (target == "wasi") {
        emit("  (import \"wasi_snapshot_preview1\" \"fd_write\"")
        emit("    (func $fd_write (param i32 i32 i32 i32) (result i32)))")
        emit("  (import \"wasi_snapshot_preview1\" \"proc_exit\"")
        emit("    (func $proc_exit (param i32)))")
    } else {
        emit("  (import \"env\" \"print_str\"")
        emit("    (func $print_str (param i32 i32)))")
    }

    emit("  (memory (export \"memory\") 2)")

    collect_strings()

    for (fi = 0; fi < fn_list_count; fi++) {
        fid = fn_ids[fi]
        gen_function(fid)
    }

    has_main = 0
    for (fi = 0; fi < fn_list_count; fi++) {
        fid = fn_ids[fi]
        if (node_name[fid] == "main") has_main = 1
    }
    if (has_main) {
        if (target == "wasi") {
            emit("  (export \"_start\" (func $main))")
        } else {
            emit("  (export \"main\" (func $main))")
        }
    }

    gen_data_segments()

    emit(")")
}

# ─── ord() implementation ──────────────────────────────────────────────────

function init_ord(    i, c) {
    for (i = 0; i <= 127; i++) {
        c = sprintf("%c", i)
        _ord[c] = i
    }
    # Extend for 128-255 (Latin-1)
    for (i = 128; i <= 255; i++) {
        # We build these via printf in shell; for awk, stick with ASCII
    }
}

function ord(c) {
    if (c in _ord) return _ord[c]
    # Fallback: use system
    return 63  # "?"
}

# ─── Main ──────────────────────────────────────────────────────────────────

BEGIN {
    node_count = 0
    child_top = 0
    str_count = 0
    data_offset = 1024
    init_ord()
}

{
    # Read all input into source
    if (NR == 1) source = $0
    else source = source "\n" $0
}

END {
    pos = 1
    lex()
    parse_program()
    generate_wat()
}
' "$SOURCE"
}

# ─── WAT to WASM compilation ───────────────────────────────────────────────

compile_wat_to_wasm() {
    local wat_file="$1"
    local wasm_file="$2"

    # Try wat2wasm
    if command -v wat2wasm &>/dev/null; then
        if wat2wasm "$wat_file" -o "$wasm_file" 2>/dev/null; then
            return 0
        fi
    fi

    # Try wasm-tools
    if command -v wasm-tools &>/dev/null; then
        if wasm-tools parse "$wat_file" -o "$wasm_file" 2>/dev/null; then
            return 0
        fi
    fi

    echo "error: no WAT compiler found. Install wabt (wat2wasm) or wasm-tools." >&2
    return 1
}

# ─── Run WASM ───────────────────────────────────────────────────────────────

run_wasm() {
    local wasm_file="$1"
    local tgt="$2"

    if [[ "$tgt" == "wasi" ]]; then
        # Try wasmtime
        if command -v wasmtime &>/dev/null; then
            wasmtime "$wasm_file"
            return $?
        fi

        # Try wasmer
        if command -v wasmer &>/dev/null; then
            wasmer "$wasm_file"
            return $?
        fi

        # Try node with WASI
        if command -v node &>/dev/null; then
            node --experimental-wasi-unstable-preview1 -e "
const fs = require('fs');
const { WASI } = require('wasi');
const wasi = new WASI({ version: 'preview1' });
const wasm = fs.readFileSync('${wasm_file}');
WebAssembly.compile(wasm).then(m =>
  WebAssembly.instantiate(m, wasi.getImportObject())
).then(i => wasi.start(i));
"
            return $?
        fi

        echo "error: no WASM runtime found. Install wasmtime, wasmer, or node." >&2
        return 1
    fi
    return 0
}

# ─── HTML Playground Generator ──────────────────────────────────────────────

generate_html() {
    local source_text="$1"
    local wasm_b64="$2"
    local html_source

    # Escape HTML special chars in source for embedding in textarea
    html_source="$(echo "$source_text" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"

    cat <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Jda Playground</title>
<style>
:root { --bg: #1e1e2e; --fg: #cdd6f4; --accent: #89b4fa; --surface: #313244;
         --code-bg: #181825; --green: #a6e3a1; --red: #f38ba8; }
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, monospace; background: var(--bg); color: var(--fg);
        display: flex; flex-direction: column; height: 100vh; }
header { padding: 1rem 2rem; border-bottom: 1px solid var(--surface); }
header h1 { color: var(--accent); font-size: 1.4rem; }
.container { display: flex; flex: 1; overflow: hidden; }
.editor, .output { flex: 1; display: flex; flex-direction: column; }
.editor { border-right: 1px solid var(--surface); }
.label { padding: 0.5rem 1rem; background: var(--surface); font-size: 0.85rem; }
textarea { flex: 1; background: var(--code-bg); color: var(--fg); border: none;
            padding: 1rem; font-family: 'JetBrains Mono', 'Fira Code', monospace;
            font-size: 0.9rem; resize: none; outline: none; tab-size: 2; }
#output { flex: 1; background: var(--code-bg); color: var(--green); padding: 1rem;
           font-family: monospace; font-size: 0.9rem; overflow-y: auto; white-space: pre-wrap; }
.toolbar { padding: 0.5rem 1rem; background: var(--surface); display: flex; gap: 1rem;
            align-items: center; }
button { background: var(--accent); color: var(--bg); border: none; padding: 0.4rem 1.2rem;
          border-radius: 4px; cursor: pointer; font-weight: bold; font-size: 0.9rem; }
button:hover { opacity: 0.9; }
.status { font-size: 0.85rem; color: var(--fg); }
</style>
</head>
<body>
<header><h1>Jda Playground</h1></header>
<div class="toolbar">
  <button onclick="runCode()">Run</button>
  <span class="status" id="status">Ready</span>
</div>
<div class="container">
  <div class="editor">
    <div class="label">Source</div>
    <textarea id="source" spellcheck="false">${html_source}</textarea>
  </div>
  <div class="output">
    <div class="label">Output</div>
    <div id="output"></div>
  </div>
</div>
<script>
${wasm_b64}
const wasmBytes = Uint8Array.from(atob(WASM_BASE64), c => c.charCodeAt(0));

async function runCode() {
  const output = document.getElementById('output');
  const status = document.getElementById('status');
  output.textContent = '';
  status.textContent = 'Running...';

  try {
    const decoder = new TextDecoder();
    let outputText = '';

    const importObject = {
      env: {
        print_str: (ptr, len) => {
          const mem = new Uint8Array(instance.exports.memory.buffer);
          const str = decoder.decode(mem.slice(ptr, ptr + len));
          outputText += str;
          output.textContent = outputText;
        }
      }
    };

    const { instance } = await WebAssembly.instantiate(wasmBytes, importObject);
    const result = instance.exports.main();
    if (outputText === '') {
      output.textContent = \`(returned \${result})\`;
    }
    status.textContent = \`Done (returned \${result})\`;
  } catch (e) {
    output.textContent = 'Error: ' + e.message;
    output.style.color = 'var(--red)';
    status.textContent = 'Error';
  }
}
</script>
</body>
</html>
HTMLEOF
}

# ─── Main Flow ──────────────────────────────────────────────────────────────

# WAT-only mode: just print WAT and exit
if [[ "$WAT_ONLY" -eq 1 ]]; then
    generate_wat
    exit 0
fi

# For all other modes, generate WAT to a temp file
TMPDIR_WAT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WAT"' EXIT

WAT_FILE="${TMPDIR_WAT}/${BASENAME}.wat"
generate_wat > "$WAT_FILE"

# HTML mode
if [[ "$DO_HTML" -eq 1 ]]; then
    WASM_FILE="${TMPDIR_WAT}/${BASENAME}.wasm"
    HTML_OUT="${OUTPUT:-${BASENAME}.html}"

    if compile_wat_to_wasm "$WAT_FILE" "$WASM_FILE"; then
        B64="$(base64 < "$WASM_FILE" | tr -d '\n')"
        WASM_B64_LINE="const WASM_BASE64 = '${B64}';"
    else
        WASM_B64_LINE="const WASM_BASE64 = '';"
        echo "Generated: ${HTML_OUT} (WAT only, no WASM runtime)" >&2
    fi

    SOURCE_TEXT="$(cat "$SOURCE")"
    generate_html "$SOURCE_TEXT" "$WASM_B64_LINE" > "$HTML_OUT"
    echo "Generated: ${HTML_OUT}"
    exit 0
fi

# Compile to WASM
WASM_OUT="${OUTPUT:-${BASENAME}.wasm}"

if ! compile_wat_to_wasm "$WAT_FILE" "$WASM_OUT"; then
    # Fallback: write WAT
    WAT_OUT="${OUTPUT:-${BASENAME}.wat}"
    cp "$WAT_FILE" "$WAT_OUT"
    echo "WAT written: ${WAT_OUT} (install wabt for binary .wasm)"
    exit 0
fi

echo "Compiled: ${WASM_OUT}"

if [[ "$DO_RUN" -eq 1 ]]; then
    run_wasm "$WASM_OUT" "$TARGET"
    exit $?
fi
