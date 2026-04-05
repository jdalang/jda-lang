#!/bin/bash
set -euo pipefail
#
# jda-arm64 — ARM64 (AArch64) cross-compiler for Jda (pure bash + awk)
#
# Compiles Jda source to aarch64-linux ELF binaries.
#
# ABI: AAPCS64
#   - x0-x7: argument/result registers
#   - x19-x28: callee-saved
#   - x29: frame pointer (FP)
#   - x30: link register (LR)
#   - sp: stack pointer (16-byte aligned)
#
# Syscall convention (Linux aarch64):
#   - x8: syscall number
#   - x0-x5: arguments
#   - svc #0
#
# Usage:
#   jda-arm64.sh <file.jda> <output>           Compile to ARM64 ELF
#   jda-arm64.sh --asm <file.jda>              Output ARM64 assembly
#   jda-arm64.sh --run <file.jda>              Compile and run via QEMU

# ─── Argument parsing ────────────────────────────────────────────────────────

ASM_MODE=0
RUN_MODE=0
SOURCE_FILE=""
OUTPUT_FILE=""

if [[ $# -eq 0 ]]; then
    echo "jda-arm64 — ARM64 cross-compiler for Jda"
    echo ""
    echo "Usage:"
    echo "  jda-arm64.sh <file.jda> <output>   Compile to ARM64 ELF"
    echo "  jda-arm64.sh --asm <file.jda>       Output ARM64 assembly"
    echo "  jda-arm64.sh --run <file.jda>       Compile and run via QEMU"
    echo ""
    echo "Target: aarch64-linux (AAPCS64 ABI)"
    echo "Requires: aarch64-linux-gnu-as/ld or Docker"
    exit 1
fi

for arg in "$@"; do
    case "$arg" in
        --asm) ASM_MODE=1 ;;
        --run) RUN_MODE=1 ;;
        *)
            if [[ -z "$SOURCE_FILE" ]]; then
                SOURCE_FILE="$arg"
            else
                OUTPUT_FILE="$arg"
            fi
            ;;
    esac
done

if [[ -z "$SOURCE_FILE" ]]; then
    echo "error: no source file specified" >&2
    exit 1
fi

if [[ ! -f "$SOURCE_FILE" ]]; then
    echo "error: file not found: $SOURCE_FILE" >&2
    exit 1
fi

if [[ -z "$OUTPUT_FILE" ]]; then
    OUTPUT_FILE="${SOURCE_FILE%.jda}"
fi

# ─── Lexer + Parser + CodeGen (all in one awk program) ───────────────────────

generate_asm() {
    awk '
# ─── Lexer ────────────────────────────────────────────────────────────────────

function lex(src,    i, c, c2, j, word, num, sval, line) {
    ntokens = 0
    i = 1
    line = 1
    while (i <= length(src)) {
        c = substr(src, i, 1)
        if (c == "\n") {
            line++; i++
        } else if (c == " " || c == "\t" || c == "\r") {
            i++
        } else if (c == ";") {
            # comment to end of line
            while (i <= length(src) && substr(src, i, 1) != "\n") i++
        } else if (c == "\"") {
            # string literal
            j = i + 1
            sval = ""
            while (j <= length(src) && substr(src, j, 1) != "\"") {
                if (substr(src, j, 1) == "\\") {
                    j++
                    c2 = substr(src, j, 1)
                    if (c2 == "n") sval = sval "\n"
                    else if (c2 == "t") sval = sval "\t"
                    else if (c2 == "\\") sval = sval "\\"
                    else if (c2 == "\"") sval = sval "\""
                    else sval = sval c2
                } else {
                    sval = sval substr(src, j, 1)
                }
                j++
            }
            ntokens++
            tok_kind[ntokens] = "STR"
            tok_val[ntokens] = sval
            tok_line[ntokens] = line
            i = j + 1
        } else if (c ~ /[0-9]/) {
            j = i
            while (j <= length(src) && substr(src, j, 1) ~ /[0-9]/) j++
            num = substr(src, i, j - i) + 0
            ntokens++
            tok_kind[ntokens] = "INT"
            tok_val[ntokens] = num
            tok_line[ntokens] = line
            i = j
        } else if (c ~ /[a-zA-Z_]/) {
            j = i
            while (j <= length(src) && substr(src, j, 1) ~ /[a-zA-Z0-9_]/) j++
            word = substr(src, i, j - i)
            ntokens++
            tok_kind[ntokens] = "ID"
            tok_val[ntokens] = word
            tok_line[ntokens] = line
            i = j
        } else if (substr(src, i, 2) == "->") {
            ntokens++; tok_kind[ntokens] = "->"; tok_val[ntokens] = "->"; tok_line[ntokens] = line; i += 2
        } else if (substr(src, i, 2) == "!=") {
            ntokens++; tok_kind[ntokens] = "!="; tok_val[ntokens] = "!="; tok_line[ntokens] = line; i += 2
        } else if (substr(src, i, 2) == "==") {
            ntokens++; tok_kind[ntokens] = "=="; tok_val[ntokens] = "=="; tok_line[ntokens] = line; i += 2
        } else if (substr(src, i, 2) == "<=") {
            ntokens++; tok_kind[ntokens] = "<="; tok_val[ntokens] = "<="; tok_line[ntokens] = line; i += 2
        } else if (substr(src, i, 2) == ">=") {
            ntokens++; tok_kind[ntokens] = ">="; tok_val[ntokens] = ">="; tok_line[ntokens] = line; i += 2
        } else {
            ntokens++; tok_kind[ntokens] = c; tok_val[ntokens] = c; tok_line[ntokens] = line; i++
        }
    }
    ntokens++
    tok_kind[ntokens] = "EOF"
    tok_val[ntokens] = ""
    tok_line[ntokens] = line
}

function peek() { return tok_kind[pos] }
function peekval() { return tok_val[pos] }
function advance(    k, v) { k = tok_kind[pos]; v = tok_val[pos]; pos++; return v }
function expect(kind,    k, v, l) {
    k = tok_kind[pos]; v = tok_val[pos]; l = tok_line[pos]
    if (k != kind) {
        print "error: expected " kind ", got " k " (" v ") at line " l > "/dev/stderr"
        exit 1
    }
    pos++
    return v
}

# ─── AST storage ──────────────────────────────────────────────────────────────
# We store the AST in flat arrays using integer node IDs.
#   node_type[id] = "int" | "var" | "binop" | "call" | "let" | "if" | "ret" | "print" | "syscall" | "expr" | "skip"
#   node_ival[id]  = integer value (for int nodes)
#   node_sval[id]  = string value (for var name, label, op, function name)
#   node_sval2[id] = secondary string (e.g., print label)
#   node_ival2[id] = secondary int (e.g., print length)
#   node_child[id,i] = child node id
#   node_nchild[id]  = number of children

function new_node(type,    id) {
    id = ++next_node
    node_type[id] = type
    node_nchild[id] = 0
    return id
}

function add_child(parent, child) {
    node_child[parent, node_nchild[parent]] = child
    node_nchild[parent]++
}

# ─── Parser ───────────────────────────────────────────────────────────────────

function parse_program(    fn_id) {
    nfunctions = 0
    nstrings = 0
    while (peek() != "EOF") {
        if (peek() == "ID" && peekval() == "fn") {
            fn_id = parse_fn()
            nfunctions++
            fn_list[nfunctions] = fn_id
        } else {
            advance()
        }
    }
}

function parse_fn(    name, nparams, pname, ptype, ret_type, body_id, fn_id, i) {
    advance()  # fn
    name = expect("ID")
    expect("(")
    nparams = 0
    while (peek() != ")") {
        pname = expect("ID")
        expect(":")
        ptype = expect("ID")
        nparams++
        param_names[name, nparams] = pname
        param_types[name, nparams] = ptype
        if (peek() == ",") advance()
    }
    expect(")")
    fn_nparams[name] = nparams
    ret_type = "void"
    if (peek() == "->") {
        advance()
        ret_type = expect("ID")
    }
    fn_ret[name] = ret_type
    expect("{")
    body_id = parse_block()
    expect("}")

    fn_id = new_node("fn")
    node_sval[fn_id] = name
    node_child[fn_id, 0] = body_id
    node_nchild[fn_id] = 1
    return fn_id
}

function parse_block(    block_id, stmt_id) {
    block_id = new_node("block")
    while (peek() != "}" && peek() != "EOF") {
        stmt_id = parse_stmt()
        add_child(block_id, stmt_id)
    }
    return block_id
}

function parse_stmt(    t, tv) {
    t = peek(); tv = peekval()
    if (t == "ID") {
        if (tv == "let") return parse_let()
        else if (tv == "if") return parse_if()
        else if (tv == "ret") return parse_ret()
        else if (tv == "print") return parse_print()
        else if (tv == "syscall") return parse_syscall()
        else return parse_expr_stmt()
    }
    advance()
    return new_node("skip")
}

function parse_let(    id, name, expr) {
    advance()  # let
    name = expect("ID")
    expect("=")
    expr = parse_expr()
    id = new_node("let")
    node_sval[id] = name
    node_child[id, 0] = expr
    node_nchild[id] = 1
    return id
}

function parse_if(    id, cond, body) {
    advance()  # if
    cond = parse_expr()
    expect("{")
    body = parse_block()
    expect("}")
    id = new_node("if")
    node_child[id, 0] = cond
    node_child[id, 1] = body
    node_nchild[id] = 2
    return id
}

function parse_ret(    id, expr) {
    advance()  # ret
    if (peek() == "}") {
        expr = new_node("int")
        node_ival[expr] = 0
    } else {
        expr = parse_expr()
    }
    id = new_node("ret")
    node_child[id, 0] = expr
    node_nchild[id] = 1
    return id
}

function parse_print(    id, has_paren, sval, label, slen, raw, i, c, hex) {
    advance()  # print
    has_paren = 0
    if (peek() == "(") { advance(); has_paren = 1 }
    sval = tok_val[pos]
    expect("STR")
    if (has_paren) expect(")")

    nstrings++
    label = ".str" (nstrings - 1)
    str_labels[nstrings] = label
    str_vals[nstrings] = sval

    # Compute byte length of the string (after escape processing)
    slen = length(sval)

    id = new_node("print")
    node_sval[id] = label
    node_ival[id] = slen
    return id
}

function parse_syscall(    id, expr) {
    advance()  # syscall
    expect("(")
    id = new_node("syscall")
    expr = parse_expr()
    add_child(id, expr)
    while (peek() == ",") {
        advance()
        expr = parse_expr()
        add_child(id, expr)
    }
    expect(")")
    return id
}

function parse_expr_stmt(    id, expr) {
    expr = parse_expr()
    id = new_node("expr")
    node_child[id, 0] = expr
    node_nchild[id] = 1
    return id
}

function parse_expr(    left, op, right) {
    left = parse_unary()
    while (peek() == "+" || peek() == "-" || peek() == "*" || peek() == "/" || \
           peek() == "==" || peek() == "!=" || peek() == "<" || peek() == ">" || \
           peek() == "<=" || peek() == ">=") {
        op = advance()
        right = parse_unary()
        id = new_node("binop")
        node_sval[id] = op
        node_child[id, 0] = left
        node_child[id, 1] = right
        node_nchild[id] = 2
        left = id
    }
    return left
}

function parse_unary(    e, id, name, nargs, arg) {
    if (peek() == "(") {
        advance()
        e = parse_expr()
        expect(")")
        return e
    }
    if (peek() == "INT") {
        id = new_node("int")
        node_ival[id] = advance() + 0
        return id
    }
    if (peek() == "ID") {
        name = advance()
        if (peek() == "(") {
            advance()
            id = new_node("call")
            node_sval[id] = name
            while (peek() != ")") {
                arg = parse_expr()
                add_child(id, arg)
                if (peek() == ",") advance()
            }
            expect(")")
            return id
        }
        id = new_node("var")
        node_sval[id] = name
        return id
    }
    print "error: unexpected " peek() " (" peekval() ") at line " tok_line[pos] > "/dev/stderr"
    exit 1
}

# ─── ARM64 Code Generator ────────────────────────────────────────────────────

function emit(line) {
    nasm++
    asm_lines[nasm] = line
}

function new_label(    l) {
    label_count++
    return ".L" label_count
}

function gen_all(    i) {
    label_count = 0
    nasm = 0

    emit(".section .text")
    emit(".global _start")
    emit("")

    for (i = 1; i <= nfunctions; i++) {
        gen_function(fn_list[i])
    }

    # _start calls main and exits
    emit("_start:")
    emit("  bl main")
    emit("  mov x8, #93")
    emit("  svc #0")
    emit("")

    # String data
    if (nstrings > 0) {
        emit(".section .rodata")
        for (i = 1; i <= nstrings; i++) {
            gen_string_data(str_labels[i], str_vals[i])
        }
        emit("")
    }
}

function gen_string_data(label, sval,    i, c, hex_bytes, ord_val, n) {
    emit(label ":")
    hex_bytes = ""
    n = length(sval)
    for (i = 1; i <= n; i++) {
        c = substr(sval, i, 1)
        ord_val = ord(c)
        if (hex_bytes != "") hex_bytes = hex_bytes ","
        hex_bytes = hex_bytes sprintf("0x%02x", ord_val)
    }
    if (hex_bytes != "") emit("  .byte " hex_bytes)
    emit(label "_nl:")
    emit("  .byte 0x0a")
}

function ord(c,    i) {
    if (!_ord_init) {
        for (i = 0; i < 256; i++) {
            _ord_map[sprintf("%c", i)] = i
        }
        _ord_init = 1
    }
    return _ord_map[c] + 0
}

function gen_function(fn_id,    name, nparams, block_id, i, n_locals, frame_size, pname, off, stmt_id) {
    name = node_sval[fn_id]
    nparams = fn_nparams[name] + 0
    block_id = node_child[fn_id, 0]

    # Collect local variable names: params first, then let-stmts
    cur_nlocals = 0
    for (i = 1; i <= nparams; i++) {
        cur_nlocals++
        cur_local_name[cur_nlocals] = param_names[name, i]
    }
    collect_lets(block_id)

    # Compute frame size (16-byte aligned)
    n_locals = cur_nlocals
    frame_size = (n_locals + 2) * 8
    if (frame_size % 16 != 0) frame_size = frame_size + (16 - frame_size % 16)
    cur_frame_size = frame_size

    # Map locals to frame offsets
    delete cur_local_off
    for (i = 1; i <= cur_nlocals; i++) {
        cur_local_off[cur_local_name[i]] = (i + 1) * 8
    }

    emit(name ":")
    # Prologue
    emit("  stp x29, x30, [sp, #-" frame_size "]!")
    emit("  mov x29, sp")

    # Save parameters to stack
    for (i = 1; i <= nparams && i <= 8; i++) {
        pname = param_names[name, i]
        off = cur_local_off[pname]
        emit("  str x" (i - 1) ", [x29, #" off "]")
    }

    # Generate body
    for (i = 0; i < node_nchild[block_id]; i++) {
        stmt_id = node_child[block_id, i]
        gen_stmt(stmt_id)
    }

    # Epilogue (fallthrough)
    emit("  mov x0, #0")
    emit("  ldp x29, x30, [sp], #" frame_size)
    emit("  ret")
    emit("")
}

function collect_lets(block_id,    i, child_id, t) {
    for (i = 0; i < node_nchild[block_id]; i++) {
        child_id = node_child[block_id, i]
        t = node_type[child_id]
        if (t == "let") {
            cur_nlocals++
            cur_local_name[cur_nlocals] = node_sval[child_id]
        } else if (t == "if") {
            # Recurse into if body
            collect_lets(node_child[child_id, 1])
        }
    }
}

function gen_stmt(stmt_id,    t, name, off, expr_id, cond_id, body_id, else_lbl, i, child_id, label, slen, nargs) {
    t = node_type[stmt_id]

    if (t == "let") {
        name = node_sval[stmt_id]
        expr_id = node_child[stmt_id, 0]
        gen_expr(expr_id)
        off = cur_local_off[name]
        emit("  str x0, [x29, #" off "]")

    } else if (t == "ret") {
        expr_id = node_child[stmt_id, 0]
        gen_expr(expr_id)
        emit("  ldp x29, x30, [sp], #" cur_frame_size)
        emit("  ret")

    } else if (t == "if") {
        cond_id = node_child[stmt_id, 0]
        body_id = node_child[stmt_id, 1]
        else_lbl = new_label()
        gen_expr(cond_id)
        emit("  cbz x0, " else_lbl)
        for (i = 0; i < node_nchild[body_id]; i++) {
            gen_stmt(node_child[body_id, i])
        }
        emit(else_lbl ":")

    } else if (t == "print") {
        label = node_sval[stmt_id]
        slen = node_ival[stmt_id]
        emit("  mov x0, #1")
        emit("  adrp x1, " label)
        emit("  add x1, x1, :lo12:" label)
        emit("  mov x2, #" slen)
        emit("  mov x8, #64")
        emit("  svc #0")
        # Newline
        emit("  mov x0, #1")
        emit("  adrp x1, " label "_nl")
        emit("  add x1, x1, :lo12:" label "_nl")
        emit("  mov x2, #1")
        emit("  mov x8, #64")
        emit("  svc #0")

    } else if (t == "syscall") {
        nargs = node_nchild[stmt_id]
        if (nargs > 0) {
            gen_expr(node_child[stmt_id, 0])
            emit("  mov x8, x0")
        }
        for (i = 1; i < nargs && i < 7; i++) {
            gen_expr(node_child[stmt_id, i])
            if (i - 1 != 0) {
                emit("  mov x" (i - 1) ", x0")
            }
        }
        emit("  svc #0")

    } else if (t == "expr") {
        gen_expr(node_child[stmt_id, 0])
    }
}

function gen_expr(expr_id,    t, val, name, off, op, left_id, right_id, cond, nargs, i) {
    t = node_type[expr_id]

    if (t == "int") {
        val = node_ival[expr_id] + 0
        if (val < 0) {
            emit("  mov x0, #" (-val))
            emit("  neg x0, x0")
        } else if (val <= 65535) {
            emit("  mov x0, #" val)
        } else {
            emit("  mov x0, #" and_bits(val, 0xffff))
            if (val > 65535) {
                emit("  movk x0, #" and_bits(rshift(val, 16), 0xffff) ", lsl #16")
            }
            if (val + 0 > 4294967295) {
                emit("  movk x0, #" and_bits(rshift(val, 32), 0xffff) ", lsl #32")
            }
            if (val + 0 > 281474976710655) {
                emit("  movk x0, #" and_bits(rshift(val, 48), 0xffff) ", lsl #48")
            }
        }

    } else if (t == "var") {
        name = node_sval[expr_id]
        off = cur_local_off[name] + 0
        emit("  ldr x0, [x29, #" off "]")

    } else if (t == "binop") {
        op = node_sval[expr_id]
        left_id = node_child[expr_id, 0]
        right_id = node_child[expr_id, 1]
        gen_expr(right_id)
        emit("  str x0, [sp, #-16]!")
        gen_expr(left_id)
        emit("  ldr x1, [sp], #16")

        if (op == "+") emit("  add x0, x0, x1")
        else if (op == "-") emit("  sub x0, x0, x1")
        else if (op == "*") emit("  mul x0, x0, x1")
        else if (op == "/") emit("  sdiv x0, x0, x1")
        else if (op == "==") { emit("  cmp x0, x1"); emit("  cset x0, eq") }
        else if (op == "!=") { emit("  cmp x0, x1"); emit("  cset x0, ne") }
        else if (op == "<")  { emit("  cmp x0, x1"); emit("  cset x0, lt") }
        else if (op == ">")  { emit("  cmp x0, x1"); emit("  cset x0, gt") }
        else if (op == "<=") { emit("  cmp x0, x1"); emit("  cset x0, le") }
        else if (op == ">=") { emit("  cmp x0, x1"); emit("  cset x0, ge") }

    } else if (t == "call") {
        name = node_sval[expr_id]
        nargs = node_nchild[expr_id]
        for (i = 0; i < nargs; i++) {
            gen_expr(node_child[expr_id, i])
            if (i < 8) emit("  str x0, [sp, #-16]!")
        }
        for (i = nargs - 1; i >= 0; i--) {
            if (i < 8) emit("  ldr x" i ", [sp], #16")
        }
        emit("  bl " name)
    }
}

# Bitwise helpers (awk lacks bitwise ops in POSIX; simulate them)
function and_bits(a, b,    result, bit, pa, pb) {
    result = 0; bit = 1
    for (pa = 0; pa < 32; pa++) {
        if (a % 2 == 1 && b % 2 == 1) result += bit
        a = int(a / 2); b = int(b / 2); bit *= 2
    }
    return result
}

function rshift(a, n,    i) {
    for (i = 0; i < n; i++) a = int(a / 2)
    return a
}

# ─── Main ─────────────────────────────────────────────────────────────────────

{
    # Read entire file into source (handle multi-line)
    if (NR == 1) source = $0
    else source = source "\n" $0
}

END {
    pos = 1
    next_node = 0
    lex(source)
    parse_program()
    gen_all()
    for (i = 1; i <= nasm; i++) {
        print asm_lines[i]
    }
}
' "$SOURCE_FILE"
}

# ─── Assembly via external tools ─────────────────────────────────────────────

assemble_with_tools() {
    local asm_source="$1"
    local output="$2"
    local tmpdir
    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT

    local asm_path="$tmpdir/prog.s"
    local obj_path="$tmpdir/prog.o"
    local bin_path="$tmpdir/prog"

    printf '%s\n' "$asm_source" > "$asm_path"

    # Try native tools first, then Docker
    local as_cmd="" ld_cmd=""
    for prefix in "aarch64-linux-gnu-" "aarch64-linux-musl-" ""; do
        if command -v "${prefix}as" &>/dev/null; then
            as_cmd="${prefix}as"
            ld_cmd="${prefix}ld"
            break
        fi
    done

    if [[ -n "$as_cmd" ]]; then
        "$as_cmd" -o "$obj_path" "$asm_path"
        "$ld_cmd" -o "$bin_path" "$obj_path" -static
    else
        # Use Docker with cross-compilation tools
        docker run --rm --platform linux/amd64 \
            -v "$tmpdir:$tmpdir" -w "$tmpdir" \
            jda-build sh -c \
            "apt-get update -qq && apt-get install -qq -y binutils-aarch64-linux-gnu >/dev/null 2>&1 && \
             aarch64-linux-gnu-as -o $obj_path $asm_path && \
             aarch64-linux-gnu-ld -o $bin_path $obj_path -static"
    fi

    cp "$bin_path" "$output"
    chmod 755 "$output"
}

run_with_qemu() {
    local binary="$1"
    if command -v qemu-aarch64 &>/dev/null; then
        qemu-aarch64 "$binary"
    else
        local abs_path
        abs_path="$(cd "$(dirname "$binary")" && pwd)/$(basename "$binary")"
        docker run --rm --platform linux/arm64 \
            -v "$(dirname "$abs_path"):/work" -w /work \
            arm64v8/ubuntu:22.04 \
            "./$( basename "$abs_path")"
    fi
}

# ─── Main logic ──────────────────────────────────────────────────────────────

ASM_OUTPUT="$(generate_asm)"

if [[ "$ASM_MODE" -eq 1 ]]; then
    printf '%s\n' "$ASM_OUTPUT"
    exit 0
fi

assemble_with_tools "$ASM_OUTPUT" "$OUTPUT_FILE"
echo "  Compiled $SOURCE_FILE -> $OUTPUT_FILE (aarch64-linux)"

if [[ "$RUN_MODE" -eq 1 ]]; then
    run_with_qemu "$OUTPUT_FILE"
fi
