#!/bin/bash
set -euo pipefail
#
# jda-macos — macOS native compiler for Jda source files (pure bash + awk)
#
# Compiles Jda source to native macOS binaries (Mach-O format).
# Supports both x86-64 and ARM64 (Apple Silicon).
#
# Usage:
#   jda-macos.sh <file.jda>                    Compile to native macOS binary
#   jda-macos.sh --arch arm64 <file.jda>       Compile for ARM64 (default on Apple Silicon)
#   jda-macos.sh --arch x86_64 <file.jda>      Compile for x86-64
#   jda-macos.sh --universal <file.jda>         Build universal binary (x86-64 + arm64)
#   jda-macos.sh --asm <file.jda>              Output assembly only
#   jda-macos.sh -o <output> <file.jda>        Specify output binary name

# ─── Detect native architecture ─────────────────────────────────────────────
detect_arch() {
    local machine
    machine=$(uname -m | tr '[:upper:]' '[:lower:]')
    case "$machine" in
        arm64|aarch64) echo "arm64" ;;
        *)             echo "x86_64" ;;
    esac
}

# ─── Assemble and link using system tools ────────────────────────────────────
assemble_macos() {
    local asm_source="$1" output_path="$2" arch="$3"
    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf '$tmp_dir'" RETURN

    local asm_path="$tmp_dir/prog.s"
    local obj_path="$tmp_dir/prog.o"

    printf '%s\n' "$asm_source" > "$asm_path"

    if ! as -arch "$arch" -o "$obj_path" "$asm_path" 2>/dev/null; then
        echo "error: assembly failed for $arch" >&2
        return 1
    fi

    if ! ld -arch "$arch" -o "$output_path" "$obj_path" \
         -lSystem -syslibroot \
         /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
         -e _main 2>/dev/null; then
        echo "error: linking failed for $arch" >&2
        return 1
    fi

    return 0
}

# ─── Build universal binary using lipo ───────────────────────────────────────
build_universal() {
    local x86_path="$1" arm64_path="$2" output_path="$3"
    if ! lipo -create -output "$output_path" "$x86_path" "$arm64_path" 2>/dev/null; then
        echo "error: lipo failed" >&2
        return 1
    fi
    return 0
}

# ─── Ad-hoc code sign ───────────────────────────────────────────────────────
ad_hoc_sign() {
    codesign -s - --force "$1" 2>/dev/null || true
}

# ─── AWK: Lexer + Parser + Codegen (single pass) ────────────────────────────
#
# The awk program reads a Jda source file and outputs assembly for the
# requested target architecture (x86_64 or arm64).
#
# Data model (all in awk arrays):
#   Tokens:  tk_kind[i], tk_val[i], tk_line[i]
#   AST nodes are NOT materialized as a tree; instead the parser calls
#   codegen functions directly in a single recursive-descent pass.
#
# We use a two-phase approach: awk phase 1 lexes+parses+codegens to stdout.

generate_asm() {
    local source_file="$1" target_arch="$2"
    awk -v ARCH="$target_arch" '
# ─── Utility ──────────────────────────────────────────────────────────
function die(msg) { print "error: " msg > "/dev/stderr"; exit 1 }

function is_digit(c)  { return c ~ /^[0-9]$/ }
function is_alpha(c)  { return c ~ /^[A-Za-z_]$/ }
function is_alnum(c)  { return c ~ /^[A-Za-z0-9_]$/ }
function is_space(c)  { return c ~ /^[ \t\r]$/ }

# ─── Lexer ────────────────────────────────────────────────────────────
function lex(    src, n, i, c, c2, j, word, num, sval) {
    src = SOURCE
    n = length(src)
    i = 1  # 1-based indexing
    LINE = 1
    NTOK = 0

    while (i <= n) {
        c = substr(src, i, 1)
        if (c == "\n") { LINE++; i++; continue }
        if (is_space(c)) { i++; continue }

        # Comment: ;;
        if (c == ";" && i+1 <= n && substr(src, i+1, 1) == ";") {
            while (i <= n && substr(src, i, 1) != "\n") i++
            continue
        }

        # String literal
        if (c == "\"") {
            j = i + 1
            sval = ""
            while (j <= n && substr(src, j, 1) != "\"") {
                if (substr(src, j, 1) == "\\") {
                    sval = sval substr(src, j, 2)
                    j += 2
                } else {
                    sval = sval substr(src, j, 1)
                    j++
                }
            }
            NTOK++
            tk_kind[NTOK] = "str"
            tk_val[NTOK] = sval
            tk_line[NTOK] = LINE
            i = j + 1
            continue
        }

        # Integer
        if (is_digit(c)) {
            j = i
            while (j <= n && is_digit(substr(src, j, 1))) j++
            num = substr(src, i, j - i) + 0
            NTOK++
            tk_kind[NTOK] = "int"
            tk_val[NTOK] = num
            tk_line[NTOK] = LINE
            i = j
            continue
        }

        # Identifier / keyword
        if (is_alpha(c)) {
            j = i
            while (j <= n && is_alnum(substr(src, j, 1))) j++
            word = substr(src, i, j - i)
            NTOK++
            if (word == "fn" || word == "let" || word == "ret" || \
                word == "if" || word == "else" || word == "loop" || \
                word == "break" || word == "print" || word == "struct" || \
                word == "enum" || word == "const" || word == "impl" || \
                word == "syscall" || word == "true" || word == "false") {
                tk_kind[NTOK] = "kw"
            } else {
                tk_kind[NTOK] = "id"
            }
            tk_val[NTOK] = word
            tk_line[NTOK] = LINE
            i = j
            continue
        }

        # Punctuation
        if (c == "(" || c == ")" || c == "{" || c == "}" || \
            c == "," || c == ";" || c == ":") {
            NTOK++
            tk_kind[NTOK] = c
            tk_val[NTOK] = c
            tk_line[NTOK] = LINE
            i++
            continue
        }

        # Arrow ->
        if (c == "-" && i+1 <= n && substr(src, i+1, 1) == ">") {
            NTOK++
            tk_kind[NTOK] = "->"
            tk_val[NTOK] = "->"
            tk_line[NTOK] = LINE
            i += 2
            continue
        }

        # Two-char operators: ==, !=, <=, >=
        c2 = (i+1 <= n) ? substr(src, i+1, 1) : ""
        if ((c == "=" || c == "!" || c == "<" || c == ">") && c2 == "=") {
            NTOK++
            tk_kind[NTOK] = c c2
            tk_val[NTOK] = c c2
            tk_line[NTOK] = LINE
            i += 2
            continue
        }

        # Single-char operators
        if (c == "+" || c == "-" || c == "*" || c == "/" || c == "%" || \
            c == "<" || c == ">" || c == "=" || c == "!") {
            NTOK++
            tk_kind[NTOK] = c
            tk_val[NTOK] = c
            tk_line[NTOK] = LINE
            i++
            continue
        }

        # Skip unknown
        i++
    }

    # EOF token
    NTOK++
    tk_kind[NTOK] = "eof"
    tk_val[NTOK] = ""
    tk_line[NTOK] = LINE
}

# ─── Parser helpers ───────────────────────────────────────────────────
function peek_kind() { return tk_kind[POS] }
function peek_val()  { return tk_val[POS] }
function advance()   { POS++ }
function expect(k,    kk, vv) {
    kk = tk_kind[POS]; vv = tk_val[POS]
    if (kk != k) die("expected " k ", got " kk " (" vv ") at line " tk_line[POS])
    POS++
}
function expect_kw(w,    kk, vv) {
    kk = tk_kind[POS]; vv = tk_val[POS]
    if (kk != "kw" || vv != w) die("expected " w ", got " vv " at line " tk_line[POS])
    POS++
}

# ─── Emit helpers ─────────────────────────────────────────────────────
function emit(s) { OUT = OUT s "\n" }

function new_label() { LABEL_COUNT++; return ".L" LABEL_COUNT }

# ─── Count locals (recursive) ────────────────────────────────────────
# We do a pre-scan of the token stream for a function body (between { })
# to count let statements. This is called before codegen.
function count_locals_in_body(start_pos, end_pos,    count, p, depth) {
    count = 0
    for (p = start_pos; p < end_pos; p++) {
        if (tk_kind[p] == "kw" && tk_val[p] == "let") count++
    }
    return count
}

# Find matching } for a { at position p (p points to {)
function find_matching_brace(p,    depth) {
    depth = 1
    p++
    while (p <= NTOK && depth > 0) {
        if (tk_kind[p] == "{") depth++
        else if (tk_kind[p] == "}") depth--
        p++
    }
    return p - 1  # position of the matching }
}

# ─── x86-64 Code Generator ───────────────────────────────────────────

function x86_gen_expr(    kind, val, name, op, nargs, i, lbl, cc) {
    kind = peek_kind(); val = peek_val()

    # Integer literal
    if (kind == "int") {
        advance()
        emit("  movq $" val ", %rax")
        return "int"
    }

    # String literal
    if (kind == "str") {
        advance()
        NSTR++
        str_val[NSTR] = val
        emit("  leaq str_" NSTR "(%rip), %rax")
        return "str"
    }

    # true/false
    if (kind == "kw" && val == "true")  { advance(); emit("  movq $1, %rax"); return "int" }
    if (kind == "kw" && val == "false") { advance(); emit("  movq $0, %rax"); return "int" }

    # syscall
    if (kind == "kw" && val == "syscall") {
        advance(); expect("(")
        # Collect args on stack
        nargs = 0
        x86_gen_expr(); nargs++; emit("  pushq %rax")
        while (peek_kind() == ",") {
            advance(); x86_gen_expr(); nargs++; emit("  pushq %rax")
        }
        expect(")")
        # Pop: first arg = syscall number -> rax, rest into rdi,rsi,rdx,r10,r8,r9
        emit("  popq %rax")
        # Remaining args popped in reverse push order (last pushed = first popped)
        # We pushed: arg0, arg1, arg2, ... argN
        # Pop order: argN, argN-1, ... arg1, arg0
        # But we already popped arg0 (actually the last pushed) above -- wrong
        # Redo: push all, then pop in correct order
        # Actually the logic above pushes as we parse left-to-right:
        #   push arg0(syscnum), push arg1, push arg2...
        # Stack top = last arg. We want rax=arg0, rdi=arg1, rsi=arg2...
        # So we need to pop in reverse. Let me restructure.

        # Actually let us use a simpler approach: store arg count, re-pop
        # The args are already on stack: top = argN, ... bottom = arg0 (syscall num)
        # We need: rax = arg0 (bottom), rdi=arg1, rsi=arg2, rdx=arg3, r10=arg4...
        # Pop top-to-bottom = argN..arg0
        # Use temporary: pop all into reverse order
        if (nargs >= 7) emit("  popq %r9")
        if (nargs >= 6) emit("  popq %r8")
        if (nargs >= 5) emit("  popq %r10")
        if (nargs >= 4) emit("  popq %rdx")
        if (nargs >= 3) emit("  popq %rsi")
        if (nargs >= 2) emit("  popq %rdi")
        if (nargs >= 1) emit("  popq %rax")
        emit("  addq $0x2000000, %rax")
        emit("  syscall")
        return "int"
    }

    # Parenthesized expression
    if (kind == "(") {
        advance()
        x86_gen_expr()
        expect(")")
        # Continue to parse binary operators after this primary
        x86_gen_binop_tail()
        return "int"
    }

    # Identifier or function call
    if (kind == "id" || (kind == "kw" && val != "fn" && val != "let" && \
        val != "ret" && val != "if" && val != "else" && val != "loop" && \
        val != "break" && val != "print" && val != "struct" && val != "enum" && \
        val != "const" && val != "impl")) {
        name = val; advance()
        if (peek_kind() == "(") {
            # Function call
            advance()
            nargs = 0
            if (peek_kind() != ")") {
                x86_gen_expr(); nargs++; emit("  pushq %rax")
                while (peek_kind() == ",") {
                    advance(); x86_gen_expr(); nargs++; emit("  pushq %rax")
                }
            }
            expect(")")
            # Pop args into registers (top of stack = last arg)
            # Stack has: bottom=arg0 ... top=argN-1
            # Need: rdi=arg0, rsi=arg1, rdx=arg2, rcx=arg3, r8=arg4, r9=arg5
            # Pop gives us argN-1 first, so pop into reverse then swap
            # Simpler: pop all into temp, then move
            # Actually pop in reverse order into correct regs
            if (nargs >= 6) emit("  popq %r9")
            if (nargs >= 5) emit("  popq %r8")
            if (nargs >= 4) emit("  popq %rcx")
            if (nargs >= 3) emit("  popq %rdx")
            if (nargs >= 2) emit("  popq %rsi")
            if (nargs >= 1) emit("  popq %rdi")
            emit("  callq _" name)
            return "int"
        }
        # Variable reference
        if (!(name in env)) die("undefined variable: " name " at line " tk_line[POS-1])
        emit("  movq -" env[name] "(%rbp), %rax")
        return "int"
    }

    # Unary minus
    if (kind == "-") {
        advance()
        emit("  movq $0, %rax")
        emit("  pushq %rax")
        x86_gen_primary()
        emit("  movq %rax, %rcx")
        emit("  popq %rax")
        emit("  subq %rcx, %rax")
        return "int"
    }

    die("unexpected token " kind " (" val ") at line " tk_line[POS])
}

# After parsing a primary, check for binary operator continuations
# This implements precedence climbing
function x86_parse_expr() {
    x86_parse_comparison()
}

function x86_parse_comparison(    op, lbl, cc) {
    x86_parse_additive()
    while (peek_kind() == "==" || peek_kind() == "!=" || peek_kind() == "<" || \
           peek_kind() == ">" || peek_kind() == "<=" || peek_kind() == ">=") {
        op = peek_kind(); advance()
        emit("  pushq %rax")
        x86_parse_additive()
        emit("  movq %rax, %rcx")
        emit("  popq %rax")
        emit("  cmpq %rcx, %rax")
        if (op == "==") cc = "sete"
        else if (op == "!=") cc = "setne"
        else if (op == "<") cc = "setl"
        else if (op == ">") cc = "setg"
        else if (op == "<=") cc = "setle"
        else if (op == ">=") cc = "setge"
        emit("  " cc " %al")
        emit("  movzbq %al, %rax")
    }
}

function x86_parse_additive(    op) {
    x86_parse_multiplicative()
    while (peek_kind() == "+" || peek_kind() == "-") {
        op = peek_kind(); advance()
        emit("  pushq %rax")
        x86_parse_multiplicative()
        emit("  movq %rax, %rcx")
        emit("  popq %rax")
        if (op == "+") emit("  addq %rcx, %rax")
        else           emit("  subq %rcx, %rax")
    }
}

function x86_parse_multiplicative(    op) {
    x86_parse_unary()
    while (peek_kind() == "*" || peek_kind() == "/" || peek_kind() == "%") {
        op = peek_kind(); advance()
        emit("  pushq %rax")
        x86_parse_unary()
        emit("  movq %rax, %rcx")
        emit("  popq %rax")
        if (op == "*") emit("  imulq %rcx, %rax")
        else if (op == "/") { emit("  cqto"); emit("  idivq %rcx") }
        else { emit("  cqto"); emit("  idivq %rcx"); emit("  movq %rdx, %rax") }
    }
}

function x86_parse_unary() {
    if (peek_kind() == "-") {
        advance()
        x86_parse_primary()
        emit("  negq %rax")
        return
    }
    x86_parse_primary()
}

function x86_parse_primary(    kind, val, name, nargs, sval, idx) {
    kind = peek_kind(); val = peek_val()

    if (kind == "int") {
        advance(); emit("  movq $" val ", %rax"); return
    }
    if (kind == "str") {
        advance()
        NSTR++; str_val[NSTR] = val
        emit("  leaq str_" NSTR "(%rip), %rax"); return
    }
    if (kind == "kw" && val == "true")  { advance(); emit("  movq $1, %rax"); return }
    if (kind == "kw" && val == "false") { advance(); emit("  movq $0, %rax"); return }

    # syscall
    if (kind == "kw" && val == "syscall") {
        advance(); expect("(")
        nargs = 0
        x86_parse_expr(); nargs++; emit("  pushq %rax")
        while (peek_kind() == ",") {
            advance(); x86_parse_expr(); nargs++; emit("  pushq %rax")
        }
        expect(")")
        if (nargs >= 7) emit("  popq %r9")
        if (nargs >= 6) emit("  popq %r8")
        if (nargs >= 5) emit("  popq %r10")
        if (nargs >= 4) emit("  popq %rdx")
        if (nargs >= 3) emit("  popq %rsi")
        if (nargs >= 2) emit("  popq %rdi")
        if (nargs >= 1) emit("  popq %rax")
        emit("  addq $0x2000000, %rax")
        emit("  syscall")
        return
    }

    # Parenthesized expression
    if (kind == "(") {
        advance(); x86_parse_expr(); expect(")"); return
    }

    # Identifier or function call
    if (kind == "id" || (kind == "kw" && \
        val != "fn" && val != "let" && val != "ret" && val != "if" && \
        val != "else" && val != "loop" && val != "break" && val != "print" && \
        val != "struct" && val != "enum" && val != "const" && val != "impl" && \
        val != "syscall")) {
        name = val; advance()
        if (peek_kind() == "(") {
            advance()
            nargs = 0
            if (peek_kind() != ")") {
                x86_parse_expr(); nargs++; emit("  pushq %rax")
                while (peek_kind() == ",") {
                    advance(); x86_parse_expr(); nargs++; emit("  pushq %rax")
                }
            }
            expect(")")
            if (nargs >= 6) emit("  popq %r9")
            if (nargs >= 5) emit("  popq %r8")
            if (nargs >= 4) emit("  popq %rcx")
            if (nargs >= 3) emit("  popq %rdx")
            if (nargs >= 2) emit("  popq %rsi")
            if (nargs >= 1) emit("  popq %rdi")
            emit("  callq _" name)
            return
        }
        if (!(name in env)) die("undefined variable: " name " at line " tk_line[POS-1])
        emit("  movq -" env[name] "(%rbp), %rax")
        return
    }

    die("unexpected token " kind " (" val ") at line " tk_line[POS])
}

function x86_gen_stmt(    kind, val, name, off, else_lbl, end_lbl, top_lbl, idx) {
    kind = peek_kind(); val = peek_val()

    # let name = expr
    if (kind == "kw" && val == "let") {
        advance()
        name = peek_val(); expect("id")
        expect("=")
        x86_parse_expr()
        SLOT++
        off = SLOT * 8
        env[name] = off
        emit("  movq %rax, -" off "(%rbp)")
        return
    }

    # assignment: name = expr
    if (kind == "id" && tk_kind[POS+1] == "=") {
        name = val; advance(); expect("=")
        x86_parse_expr()
        if (!(name in env)) die("undefined variable: " name)
        off = env[name]
        emit("  movq %rax, -" off "(%rbp)")
        return
    }

    # ret expr
    if (kind == "kw" && val == "ret") {
        advance()
        x86_parse_expr()
        emit("  addq $" FRAME_SIZE ", %rsp")
        emit("  popq %rbp")
        emit("  retq")
        return
    }

    # if cond { ... } else { ... }
    if (kind == "kw" && val == "if") {
        advance()
        else_lbl = new_label()
        end_lbl = new_label()
        x86_parse_expr()
        emit("  testq %rax, %rax")
        emit("  je " else_lbl)
        expect("{")
        while (peek_kind() != "}") x86_gen_stmt()
        expect("}")
        if (peek_kind() == "kw" && peek_val() == "else") {
            emit("  jmp " end_lbl)
            emit(else_lbl ":")
            advance(); expect("{")
            while (peek_kind() != "}") x86_gen_stmt()
            expect("}")
            emit(end_lbl ":")
        } else {
            emit(else_lbl ":")
        }
        return
    }

    # loop cond { ... }
    if (kind == "kw" && val == "loop") {
        advance()
        top_lbl = new_label()
        end_lbl = new_label()
        # Save and set loop end label
        saved_loop_end = LOOP_END
        LOOP_END = end_lbl
        emit(top_lbl ":")
        x86_parse_expr()
        emit("  testq %rax, %rax")
        emit("  je " end_lbl)
        expect("{")
        while (peek_kind() != "}") x86_gen_stmt()
        expect("}")
        emit("  jmp " top_lbl)
        emit(end_lbl ":")
        LOOP_END = saved_loop_end
        return
    }

    # break
    if (kind == "kw" && val == "break") {
        advance()
        emit("  jmp " LOOP_END)
        return
    }

    # print expr
    if (kind == "kw" && val == "print") {
        advance()
        if (peek_kind() == "str") {
            val = peek_val(); advance()
            NSTR++
            str_val[NSTR] = val
            idx = NSTR
            emit("  movq $0x2000004, %rax")
            emit("  movq $1, %rdi")
            emit("  leaq str_" idx "(%rip), %rsi")
            emit("  movq $str_" idx "_len, %rdx")
            emit("  syscall")
        } else {
            x86_parse_expr()
            emit("  movq %rax, %rdi")
            emit("  callq _print_int")
        }
        return
    }

    # Expression statement
    x86_parse_expr()
}

function x86_gen_function(    fname, label, nparams, i, pname, num_locals, \
                              body_start, body_end, param_regs) {
    expect_kw("fn")
    fname = peek_val(); expect("id")
    expect("(")

    # Parse parameters
    nparams = 0
    delete env
    SLOT = 0

    if (peek_kind() != ")") {
        nparams++
        pname = peek_val(); expect("id")
        expect(":")
        while (peek_kind() != "," && peek_kind() != ")") advance()
        SLOT++
        env[pname] = SLOT * 8

        while (peek_kind() == ",") {
            advance()
            nparams++
            pname = peek_val(); expect("id")
            expect(":")
            while (peek_kind() != "," && peek_kind() != ")") advance()
            SLOT++
            env[pname] = SLOT * 8
        }
    }
    expect(")")

    # Skip return type
    if (peek_kind() == "->") {
        advance()
        while (peek_kind() != "{") advance()
    }

    # Count locals in body (scan ahead)
    body_start = POS
    expect("{")
    body_end = find_matching_brace(POS - 1)
    num_locals = count_locals_in_body(POS, body_end)
    # Reset POS to body_start + 1 (after {)
    POS = body_start
    expect("{")

    # Emit function prologue
    label = (fname == "main") ? "_main" : ("_" fname)
    FRAME_SIZE = (num_locals + nparams + 1) * 8
    # Align to 16 bytes, minimum 16
    FRAME_SIZE = int((FRAME_SIZE + 15) / 16) * 16
    if (FRAME_SIZE < 16) FRAME_SIZE = 16

    emit(label ":")
    emit("  pushq %rbp")
    emit("  movq %rsp, %rbp")
    emit("  subq $" FRAME_SIZE ", %rsp")

    # Store parameters from registers
    split("%rdi %rsi %rdx %rcx %r8 %r9", _pregs, " ")
    for (i = 1; i <= nparams && i <= 6; i++) {
        emit("  movq " _pregs[i] ", -" (i * 8) "(%rbp)")
    }

    # Generate body
    while (peek_kind() != "}") x86_gen_stmt()
    expect("}")

    # Epilogue (default return 0)
    emit("  xorl %eax, %eax")
    emit("  addq $" FRAME_SIZE ", %rsp")
    emit("  popq %rbp")
    emit("  retq")
    emit("")
}

# ─── ARM64 Code Generator ────────────────────────────────────────────

function arm64_parse_expr() {
    arm64_parse_comparison()
}

function arm64_parse_comparison(    op, cc) {
    arm64_parse_additive()
    while (peek_kind() == "==" || peek_kind() == "!=" || peek_kind() == "<" || \
           peek_kind() == ">" || peek_kind() == "<=" || peek_kind() == ">=") {
        op = peek_kind(); advance()
        emit("  str x0, [sp, #-16]!")
        arm64_parse_additive()
        emit("  mov x1, x0")
        emit("  ldr x0, [sp], #16")
        emit("  cmp x0, x1")
        if (op == "==") cc = "eq"
        else if (op == "!=") cc = "ne"
        else if (op == "<") cc = "lt"
        else if (op == ">") cc = "gt"
        else if (op == "<=") cc = "le"
        else if (op == ">=") cc = "ge"
        emit("  cset x0, " cc)
    }
}

function arm64_parse_additive(    op) {
    arm64_parse_multiplicative()
    while (peek_kind() == "+" || peek_kind() == "-") {
        op = peek_kind(); advance()
        emit("  str x0, [sp, #-16]!")
        arm64_parse_multiplicative()
        emit("  mov x1, x0")
        emit("  ldr x0, [sp], #16")
        if (op == "+") emit("  add x0, x0, x1")
        else           emit("  sub x0, x0, x1")
    }
}

function arm64_parse_multiplicative(    op) {
    arm64_parse_unary()
    while (peek_kind() == "*" || peek_kind() == "/" || peek_kind() == "%") {
        op = peek_kind(); advance()
        emit("  str x0, [sp, #-16]!")
        arm64_parse_unary()
        emit("  mov x1, x0")
        emit("  ldr x0, [sp], #16")
        if (op == "*") emit("  mul x0, x0, x1")
        else if (op == "/") emit("  sdiv x0, x0, x1")
        else { emit("  sdiv x2, x0, x1"); emit("  msub x0, x2, x1, x0") }
    }
}

function arm64_parse_unary() {
    if (peek_kind() == "-") {
        advance()
        arm64_parse_primary()
        emit("  neg x0, x0")
        return
    }
    arm64_parse_primary()
}

function arm64_parse_primary(    kind, val, name, nargs, idx, lo, hi) {
    kind = peek_kind(); val = peek_val()

    if (kind == "int") {
        advance()
        if (val + 0 >= 0 && val + 0 < 65536) {
            emit("  mov x0, #" val)
        } else {
            lo = and_bits(val + 0, 65535)
            hi = rshift_16(val + 0)
            emit("  mov x0, #" lo)
            if (hi > 0) emit("  movk x0, #" hi ", lsl #16")
        }
        return
    }
    if (kind == "str") {
        advance()
        NSTR++; str_val[NSTR] = val
        emit("  adrp x0, str_" NSTR "@PAGE")
        emit("  add x0, x0, str_" NSTR "@PAGEOFF")
        return
    }
    if (kind == "kw" && val == "true")  { advance(); emit("  mov x0, #1"); return }
    if (kind == "kw" && val == "false") { advance(); emit("  mov x0, #0"); return }

    # syscall
    if (kind == "kw" && val == "syscall") {
        advance(); expect("(")
        nargs = 0
        arm64_parse_expr(); nargs++; emit("  str x0, [sp, #-16]!")
        while (peek_kind() == ",") {
            advance(); arm64_parse_expr(); nargs++; emit("  str x0, [sp, #-16]!")
        }
        expect(")")
        # Pop: syscall num -> x16, args -> x0..x5
        # Stack has bottom=arg0(syscnum) ... top=argN
        if (nargs >= 7) emit("  ldr x5, [sp], #16")
        if (nargs >= 6) emit("  ldr x4, [sp], #16")
        if (nargs >= 5) emit("  ldr x3, [sp], #16")
        if (nargs >= 4) emit("  ldr x2, [sp], #16")
        if (nargs >= 3) emit("  ldr x1, [sp], #16")
        if (nargs >= 2) emit("  ldr x0, [sp], #16")
        if (nargs >= 1) emit("  ldr x16, [sp], #16")
        emit("  svc #0x80")
        return
    }

    # Parenthesized
    if (kind == "(") {
        advance(); arm64_parse_expr(); expect(")"); return
    }

    # Identifier or function call
    if (kind == "id" || (kind == "kw" && \
        val != "fn" && val != "let" && val != "ret" && val != "if" && \
        val != "else" && val != "loop" && val != "break" && val != "print" && \
        val != "struct" && val != "enum" && val != "const" && val != "impl" && \
        val != "syscall")) {
        name = val; advance()
        if (peek_kind() == "(") {
            advance()
            nargs = 0
            if (peek_kind() != ")") {
                arm64_parse_expr(); nargs++; emit("  str x0, [sp, #-16]!")
                while (peek_kind() == ",") {
                    advance(); arm64_parse_expr(); nargs++; emit("  str x0, [sp, #-16]!")
                }
            }
            expect(")")
            # Pop into x0..x7 (reverse stack order)
            if (nargs >= 8) emit("  ldr x7, [sp], #16")
            if (nargs >= 7) emit("  ldr x6, [sp], #16")
            if (nargs >= 6) emit("  ldr x5, [sp], #16")
            if (nargs >= 5) emit("  ldr x4, [sp], #16")
            if (nargs >= 4) emit("  ldr x3, [sp], #16")
            if (nargs >= 3) emit("  ldr x2, [sp], #16")
            if (nargs >= 2) emit("  ldr x1, [sp], #16")
            if (nargs >= 1) emit("  ldr x0, [sp], #16")
            emit("  bl _" name)
            return
        }
        if (!(name in env)) die("undefined variable: " name " at line " tk_line[POS-1])
        emit("  ldr x0, [x29, #" env[name] "]")
        return
    }

    die("unexpected token " kind " (" val ") at line " tk_line[POS])
}

function arm64_gen_stmt(    kind, val, name, off, else_lbl, end_lbl, top_lbl, idx, saved_loop_end) {
    kind = peek_kind(); val = peek_val()

    # let name = expr
    if (kind == "kw" && val == "let") {
        advance()
        name = peek_val(); expect("id")
        expect("=")
        arm64_parse_expr()
        SLOT++
        off = SLOT * 8
        env[name] = off
        emit("  str x0, [x29, #" off "]")
        return
    }

    # assignment: name = expr
    if (kind == "id" && tk_kind[POS+1] == "=") {
        name = val; advance(); expect("=")
        arm64_parse_expr()
        if (!(name in env)) die("undefined variable: " name)
        off = env[name]
        emit("  str x0, [x29, #" off "]")
        return
    }

    # ret expr
    if (kind == "kw" && val == "ret") {
        advance()
        arm64_parse_expr()
        emit("  ldp x29, x30, [sp], #" FRAME_SIZE)
        emit("  ret")
        return
    }

    # if cond { ... } else { ... }
    if (kind == "kw" && val == "if") {
        advance()
        else_lbl = new_label()
        end_lbl = new_label()
        arm64_parse_expr()
        emit("  cbz x0, " else_lbl)
        expect("{")
        while (peek_kind() != "}") arm64_gen_stmt()
        expect("}")
        if (peek_kind() == "kw" && peek_val() == "else") {
            emit("  b " end_lbl)
            emit(else_lbl ":")
            advance(); expect("{")
            while (peek_kind() != "}") arm64_gen_stmt()
            expect("}")
            emit(end_lbl ":")
        } else {
            emit(else_lbl ":")
        }
        return
    }

    # loop cond { ... }
    if (kind == "kw" && val == "loop") {
        advance()
        top_lbl = new_label()
        end_lbl = new_label()
        saved_loop_end = LOOP_END
        LOOP_END = end_lbl
        emit(top_lbl ":")
        arm64_parse_expr()
        emit("  cbz x0, " end_lbl)
        expect("{")
        while (peek_kind() != "}") arm64_gen_stmt()
        expect("}")
        emit("  b " top_lbl)
        emit(end_lbl ":")
        LOOP_END = saved_loop_end
        return
    }

    # break
    if (kind == "kw" && val == "break") {
        advance()
        emit("  b " LOOP_END)
        return
    }

    # print expr
    if (kind == "kw" && val == "print") {
        advance()
        if (peek_kind() == "str") {
            val = peek_val(); advance()
            NSTR++
            str_val[NSTR] = val
            idx = NSTR
            emit("  mov x0, #1")
            emit("  adrp x1, str_" idx "@PAGE")
            emit("  add x1, x1, str_" idx "@PAGEOFF")
            emit("  mov x2, #str_" idx "_len")
            emit("  mov x16, #4")
            emit("  svc #0x80")
        } else {
            arm64_parse_expr()
            emit("  bl _print_int")
        }
        return
    }

    # Expression statement
    arm64_parse_expr()
}

function arm64_gen_function(    fname, label, nparams, i, pname, num_locals, \
                                body_start, body_end) {
    expect_kw("fn")
    fname = peek_val(); expect("id")
    expect("(")

    nparams = 0
    delete env
    SLOT = 1  # slot 0 reserved for x29/x30 (2 regs = 16 bytes, but we use slots of 8)

    if (peek_kind() != ")") {
        nparams++
        pname = peek_val(); expect("id")
        expect(":")
        while (peek_kind() != "," && peek_kind() != ")") advance()
        SLOT++
        env[pname] = SLOT * 8

        while (peek_kind() == ",") {
            advance()
            nparams++
            pname = peek_val(); expect("id")
            expect(":")
            while (peek_kind() != "," && peek_kind() != ")") advance()
            SLOT++
            env[pname] = SLOT * 8
        }
    }
    expect(")")

    # Skip return type
    if (peek_kind() == "->") {
        advance()
        while (peek_kind() != "{") advance()
    }

    # Count locals
    body_start = POS
    expect("{")
    body_end = find_matching_brace(POS - 1)
    num_locals = count_locals_in_body(POS, body_end)
    POS = body_start
    expect("{")

    label = (fname == "main") ? "_main" : ("_" fname)
    FRAME_SIZE = (num_locals + nparams + 4) * 8  # +4 for x29, x30, padding
    FRAME_SIZE = int((FRAME_SIZE + 15) / 16) * 16
    if (FRAME_SIZE < 32) FRAME_SIZE = 32

    emit(label ":")
    emit("  stp x29, x30, [sp, #-" FRAME_SIZE "]!")
    emit("  mov x29, sp")

    # Store parameters from registers x0-x7
    for (i = 1; i <= nparams && i <= 8; i++) {
        emit("  str x" (i-1) ", [x29, #" env[_fn_params[i]] "]")
    }

    while (peek_kind() != "}") arm64_gen_stmt()
    expect("}")

    emit("  mov x0, #0")
    emit("  ldp x29, x30, [sp], #" FRAME_SIZE)
    emit("  ret")
    emit("")
}

# We need to track param names for arm64 store — fix arm64_gen_function
# to store param names as we parse them.

# Override: inline the param tracking
function arm64_gen_function_v2(    fname, label, nparams, i, pname, num_locals, \
                                   body_start, body_end, pnames) {
    expect_kw("fn")
    fname = peek_val(); expect("id")
    expect("(")

    nparams = 0
    delete env
    SLOT = 1

    if (peek_kind() != ")") {
        nparams++
        pname = peek_val(); expect("id")
        expect(":")
        while (peek_kind() != "," && peek_kind() != ")") advance()
        SLOT++
        env[pname] = SLOT * 8
        pnames[nparams] = pname

        while (peek_kind() == ",") {
            advance()
            nparams++
            pname = peek_val(); expect("id")
            expect(":")
            while (peek_kind() != "," && peek_kind() != ")") advance()
            SLOT++
            env[pname] = SLOT * 8
            pnames[nparams] = pname
        }
    }
    expect(")")

    if (peek_kind() == "->") {
        advance()
        while (peek_kind() != "{") advance()
    }

    body_start = POS
    expect("{")
    body_end = find_matching_brace(POS - 1)
    num_locals = count_locals_in_body(POS, body_end)
    POS = body_start
    expect("{")

    label = (fname == "main") ? "_main" : ("_" fname)
    FRAME_SIZE = (num_locals + nparams + 4) * 8
    FRAME_SIZE = int((FRAME_SIZE + 15) / 16) * 16
    if (FRAME_SIZE < 32) FRAME_SIZE = 32

    emit(label ":")
    emit("  stp x29, x30, [sp, #-" FRAME_SIZE "]!")
    emit("  mov x29, sp")

    for (i = 1; i <= nparams && i <= 8; i++) {
        emit("  str x" (i-1) ", [x29, #" env[pnames[i]] "]")
    }

    while (peek_kind() != "}") arm64_gen_stmt()
    expect("}")

    emit("  mov x0, #0")
    emit("  ldp x29, x30, [sp], #" FRAME_SIZE)
    emit("  ret")
    emit("")
}

# ─── Bitwise helpers (awk lacks bitwise ops) ─────────────────────────
function and_bits(v, mask,    result, bit, vm, mm) {
    result = 0; bit = 1; vm = int(v); mm = int(mask)
    while (vm > 0 || mm > 0) {
        if ((vm % 2) == 1 && (mm % 2) == 1) result += bit
        vm = int(vm / 2); mm = int(mm / 2); bit *= 2
        if (bit > 1048576) break
    }
    return result
}

function rshift_16(v) { return int(int(v) / 65536) }

# ─── String data emission ────────────────────────────────────────────
function emit_string_data(    i, s, j, ch, hex_bytes, byte_count, escaped) {
    if (NSTR == 0) return

    if (ARCH == "x86_64") {
        emit(".section __TEXT,__cstring,cstring_literals")
    } else {
        emit(".section __TEXT,__cstring,cstring_literals")
    }

    for (i = 1; i <= NSTR; i++) {
        s = str_val[i]
        emit("str_" i ":")
        # Convert escape sequences and emit as .byte directives
        hex_bytes = ""
        byte_count = 0
        for (j = 1; j <= length(s); j++) {
            ch = substr(s, j, 1)
            if (ch == "\\" && j + 1 <= length(s)) {
                escaped = substr(s, j+1, 1)
                if (escaped == "n") { hex_bytes = hex_bytes (hex_bytes == "" ? "" : ",") "0x0a"; byte_count++; j++ }
                else if (escaped == "t") { hex_bytes = hex_bytes (hex_bytes == "" ? "" : ",") "0x09"; byte_count++; j++ }
                else if (escaped == "\\") { hex_bytes = hex_bytes (hex_bytes == "" ? "" : ",") "0x5c"; byte_count++; j++ }
                else if (escaped == "\"") { hex_bytes = hex_bytes (hex_bytes == "" ? "" : ",") "0x22"; byte_count++; j++ }
                else { hex_bytes = hex_bytes (hex_bytes == "" ? "" : ",") sprintf("0x%02x", _ord(ch)); byte_count++ }
            } else {
                hex_bytes = hex_bytes (hex_bytes == "" ? "" : ",") sprintf("0x%02x", _ord(ch))
                byte_count++
            }
        }
        if (hex_bytes != "") emit("  .byte " hex_bytes)
        emit("str_" i "_len = " byte_count)
    }
    emit("")
}

# Char to ASCII value
function _ord(c,    i) {
    if (!_ord_init) {
        for (i = 0; i < 256; i++) _ord_table[sprintf("%c", i)] = i
        _ord_init = 1
    }
    return (c in _ord_table) ? _ord_table[c] : 63  # 63 = ?
}

# ─── Main entry point ────────────────────────────────────────────────
BEGIN {
    OUT = ""
    NSTR = 0
    LABEL_COUNT = 0
    SLOT = 0
    FRAME_SIZE = 0
    LOOP_END = ""
    POS = 1
}

{
    # Read entire file into SOURCE (concatenate all lines)
    if (NR == 1) SOURCE = $0
    else SOURCE = SOURCE "\n" $0
}

END {
    # Lex
    lex()

    # Emit header
    if (ARCH == "x86_64") {
        emit(".section __TEXT,__text,regular,pure_instructions")
        emit(".globl _main")
        emit("")
    } else {
        emit(".section __TEXT,__text,regular,pure_instructions")
        emit(".globl _main")
        emit(".p2align 2")
        emit("")
    }

    # Parse and generate functions
    POS = 1
    while (peek_kind() != "eof") {
        if (peek_kind() == "kw" && peek_val() == "fn") {
            if (ARCH == "x86_64") {
                x86_gen_function()
            } else {
                arm64_gen_function_v2()
            }
        } else {
            advance()  # skip non-function top-level tokens
        }
    }

    # Emit string data
    emit_string_data()

    # Print output (strip trailing newline)
    printf "%s", OUT
}
' "$source_file"
}

# ─── CLI Argument Parsing ────────────────────────────────────────────────────

arch=$(detect_arch)
asm_only=false
universal=false
output=""
source_file=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            arch="$2"; shift 2 ;;
        --asm)
            asm_only=true; shift ;;
        --universal)
            universal=true; shift ;;
        -o)
            output="$2"; shift 2 ;;
        *)
            source_file="$1"; shift ;;
    esac
done

if [[ -z "$source_file" ]]; then
    echo "jda-macos — macOS native compiler for Jda"
    echo ""
    echo "Usage:"
    echo "  jda-macos.sh <file.jda>                    Compile to native macOS binary"
    echo "  jda-macos.sh --arch arm64 <file.jda>       Compile for ARM64"
    echo "  jda-macos.sh --arch x86_64 <file.jda>      Compile for x86-64"
    echo "  jda-macos.sh --universal <file.jda>         Universal binary (both archs)"
    echo "  jda-macos.sh --asm <file.jda>              Output assembly only"
    echo "  jda-macos.sh -o <output> <file.jda>        Specify output name"
    exit 1
fi

if [[ ! -f "$source_file" ]]; then
    echo "error: source file not found: $source_file" >&2
    exit 1
fi

# Default output name: basename without extension
if [[ -z "$output" ]]; then
    output=$(basename "$source_file" .jda)
fi

# ─── Assembly-only mode ──────────────────────────────────────────────────────
if $asm_only; then
    if $universal || [[ "$arch" == "x86_64" ]]; then
        echo "; x86-64 macOS assembly"
        generate_asm "$source_file" "x86_64"
    fi
    if $universal || [[ "$arch" == "arm64" ]]; then
        if $universal; then
            echo ""
            echo "; ARM64 macOS assembly"
        fi
        generate_asm "$source_file" "arm64"
    fi
    exit 0
fi

# ─── Compile ─────────────────────────────────────────────────────────────────
if $universal; then
    tmp_dir=$(mktemp -d)
    trap "rm -rf '$tmp_dir'" EXIT

    x86_path="$tmp_dir/${output}_x86_64"
    arm_path="$tmp_dir/${output}_arm64"

    asm_x86=$(generate_asm "$source_file" "x86_64")
    if ! assemble_macos "$asm_x86" "$x86_path" "x86_64"; then
        echo "error: x86-64 build failed" >&2
        exit 1
    fi

    asm_arm=$(generate_asm "$source_file" "arm64")
    if ! assemble_macos "$asm_arm" "$arm_path" "arm64"; then
        echo "error: ARM64 build failed" >&2
        exit 1
    fi

    if ! build_universal "$x86_path" "$arm_path" "$output"; then
        echo "error: universal binary creation failed" >&2
        exit 1
    fi

    ad_hoc_sign "$output"
    echo "Universal binary: $output"
    file "$output"
else
    asm_output=$(generate_asm "$source_file" "$arch")
    if ! assemble_macos "$asm_output" "$output" "$arch"; then
        exit 1
    fi

    ad_hoc_sign "$output"
    echo "Built: $output ($arch)"
    file "$output"
fi
