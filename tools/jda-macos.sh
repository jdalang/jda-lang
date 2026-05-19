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
         -e _main 2>&1 | grep -v "^$"; then
        :
    fi
    if [ ! -f "$output_path" ]; then
        echo "error: linking failed for $arch" >&2
        ld -arch "$arch" -o "$output_path" "$obj_path" \
           -lSystem -syslibroot \
           /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
           -e _main 2>&1 | head -30 >&2
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
    i = 1
    LINE = 1
    NTOK = 0

    while (i <= n) {
        c = substr(src, i, 1)
        if (c == "\n") { LINE++; i++; continue }
        if (is_space(c)) { i++; continue }

        # Comment: //
        if (c == "/" && i+1 <= n && substr(src, i+1, 1) == "/") {
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

        # Integer (with optional type suffix i64, u8, etc.)
        if (is_digit(c)) {
            j = i
            # Check for hex literal: 0x...
            if (c == "0" && j+1 <= n && tolower(substr(src, j+1, 1)) == "x") {
                j += 2  # skip "0x"
                hex_str = "0"
                while (j <= n) {
                    hc = tolower(substr(src, j, 1))
                    if (hc >= "0" && hc <= "9") { hex_str = bigmul_add(hex_str, 16, hc - "0"); j++ }
                    else if (hc >= "a" && hc <= "f") { hex_str = bigmul_add(hex_str, 16, index("abcdef", hc) + 9); j++ }
                    else break
                }
                num = hex_str
            } else {
                while (j <= n && is_digit(substr(src, j, 1))) j++
                num = substr(src, i, j - i) + 0
            }
            # Skip type suffix like i64, u32, i8 (only known suffixes)
            if (j <= n && is_alpha(substr(src, j, 1))) {
                tsuf = ""; tj = j
                while (tj <= n && is_alnum(substr(src, tj, 1))) { tsuf = tsuf substr(src, tj, 1); tj++ }
                if (tsuf == "i64" || tsuf == "i32" || tsuf == "i8" || tsuf == "u64" || tsuf == "u32" || tsuf == "u8" || tsuf == "f64" || tsuf == "f32") j = tj
            }
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
            if (word == "fn"       || word == "let"      || word == "ret"  || \
                word == "if"       || word == "else"     || word == "loop" || \
                word == "break"    || word == "print"    || word == "struct" || \
                word == "enum"     || word == "const"    || word == "impl"  || \
                word == "syscall"  || word == "true"     || word == "false" || \
                word == "in"       || word == "not"      || word == "and"   || \
                word == "or"       || word == "xor"      || word == "as"    || \
                word == "match"    || word == "continue" || word == "for"   || \
                word == "null"     || word == "for") {
                tk_kind[NTOK] = "kw"
            } else {
                tk_kind[NTOK] = "id"
            }
            tk_val[NTOK] = word
            tk_line[NTOK] = LINE
            i = j
            continue
        }

        # Character literal: x (single char, e.g., / or *)
        if (c == "'"'"'") {
            j = i + 1
            chval = 0
            if (j <= n && substr(src, j, 1) == "\\") {
                esc = substr(src, j+1, 1)
                if      (esc == "n") chval = 10
                else if (esc == "t") chval = 9
                else if (esc == "r") chval = 13
                else if (esc == "0") chval = 0
                else                 chval = _ord(esc)
                j += 2
            } else if (j <= n) {
                chval = _ord(substr(src, j, 1))
                j++
            }
            if (j <= n && substr(src, j, 1) == "'"'"'") j++
            NTOK++; tk_kind[NTOK] = "int"; tk_val[NTOK] = chval; tk_line[NTOK] = LINE
            i = j; continue
        }

        # Two-char logical operators && ||
        if (c == "&" && i+1 <= n && substr(src, i+1, 1) == "&") {
            NTOK++; tk_kind[NTOK] = "&&"; tk_val[NTOK] = "&&"; tk_line[NTOK] = LINE; i += 2; continue
        }
        if (c == "|" && i+1 <= n && substr(src, i+1, 1) == "|") {
            NTOK++; tk_kind[NTOK] = "||"; tk_val[NTOK] = "||"; tk_line[NTOK] = LINE; i += 2; continue
        }

        # Punctuation (including . & [ ])
        if (c == "(" || c == ")" || c == "{" || c == "}" || \
            c == "," || c == ";" || c == ":" || c == "." || \
            c == "&" || c == "[" || c == "]" || c == "@" || c == "#") {
            NTOK++
            tk_kind[NTOK] = c
            tk_val[NTOK] = c
            tk_line[NTOK] = LINE
            i++
            continue
        }

        # Arrow -> and fat-arrow =>
        if (c == "-" && i+1 <= n && substr(src, i+1, 1) == ">") {
            NTOK++; tk_kind[NTOK] = "->"; tk_val[NTOK] = "->"; tk_line[NTOK] = LINE; i += 2; continue
        }
        if (c == "=" && i+1 <= n && substr(src, i+1, 1) == ">") {
            NTOK++; tk_kind[NTOK] = "=>"; tk_val[NTOK] = "=>"; tk_line[NTOK] = LINE; i += 2; continue
        }

        # Two-char shifts >> <<
        c2 = (i+1 <= n) ? substr(src, i+1, 1) : ""
        if (c == ">" && c2 == ">") {
            NTOK++; tk_kind[NTOK] = ">>"; tk_val[NTOK] = ">>"; tk_line[NTOK] = LINE; i += 2; continue
        }
        if (c == "<" && c2 == "<") {
            NTOK++; tk_kind[NTOK] = "<<"; tk_val[NTOK] = "<<"; tk_line[NTOK] = LINE; i += 2; continue
        }

        # Two-char operators: == != <= >=
        if ((c == "=" || c == "!" || c == "<" || c == ">") && c2 == "=") {
            NTOK++; tk_kind[NTOK] = c c2; tk_val[NTOK] = c c2; tk_line[NTOK] = LINE; i += 2; continue
        }

        # Single-char operators
        if (c == "+" || c == "-" || c == "*" || c == "/" || c == "%" || \
            c == "<" || c == ">" || c == "=" || c == "!" || c == "^" || c == "|") {
            NTOK++; tk_kind[NTOK] = c; tk_val[NTOK] = c; tk_line[NTOK] = LINE; i++; continue
        }

        # Skip unknown
        i++
    }

    NTOK++; tk_kind[NTOK] = "eof"; tk_val[NTOK] = ""; tk_line[NTOK] = LINE
}

# ─── Parser helpers ───────────────────────────────────────────────────
function peek_kind()  { return tk_kind[POS] }
function peek_val()   { return tk_val[POS] }
function advance()    { POS++ }
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
function emit(s)    { OUT = OUT s "\n" }
function new_label() { LABEL_COUNT++; return ".L" LABEL_COUNT }

# ─── Count locals (pre-scan of function body) ─────────────────────────
function count_locals_in_body(start_pos, end_pos,    count, p, sn) {
    count = 0
    for (p = start_pos; p < end_pos; p++) {
        if (tk_kind[p] == "kw" && tk_val[p] == "let") count++
        # Struct literal allocation: TypeName { ... }
        if (tk_kind[p] == "id" && tk_kind[p+1] == "{" && (tk_val[p] in struct_size)) {
            count += int(struct_size[tk_val[p]] / 8) + 1
        }
        # Fixed array: [N]type or [CONST]type
        if (tk_kind[p] == "[") {
            if (tk_kind[p+1] == "int") {
                count += int(tk_val[p+1] / 8) + 2
            } else if (tk_kind[p+1] == "id" && (tk_val[p+1] in const_val)) {
                count += int(const_val[tk_val[p+1]] / 8) + 2
            }
        }
    }
    return count
}

# Find matching } for a { at position p
function find_matching_brace(p,    depth) {
    depth = 1; p++
    while (p <= NTOK && depth > 0) {
        if (tk_kind[p] == "{") depth++
        else if (tk_kind[p] == "}") depth--
        p++
    }
    return p - 1
}

# ─── Pre-scan: collect consts, struct definitions, and global vars ───
function prescan(    saved_pos, sname, fname_f, offset, depth, gname, \
                     field_sz, ne, cn, et) {
    saved_pos = POS
    POS = 1
    depth = 0
    GLOBAL_SIZE = 0
    while (peek_kind() != "eof") {
        if (peek_kind() == "kw" && peek_val() == "const") {
            advance()
            if (peek_kind() != "id") { advance(); continue }
            fname_f = peek_val(); advance()
            if (peek_kind() != "=") continue
            advance()
            if (peek_kind() == "int") {
                const_val[fname_f] = peek_val() + 0; advance()
            }
        } else if (peek_kind() == "kw" && peek_val() == "struct") {
            advance()
            if (peek_kind() != "id") { advance(); continue }
            sname = peek_val(); advance()
            if (peek_kind() != "{") continue
            advance()
            depth++
            offset = 0
            while (peek_kind() != "}" && peek_kind() != "eof") {
                if (peek_kind() == "id" && tk_kind[POS+1] == ":") {
                    fname_f = peek_val(); advance()
                    advance()  # :
                    struct_field_off[sname ":" fname_f] = offset
                    field_sz = 8
                    # Check for array field: [N]type or [CONST]type
                    if (peek_kind() == "[") {
                        advance()  # consume [
                        if (peek_kind() == "int") {
                            ne = peek_val() + 0; advance()
                            if (peek_kind() == "]") advance()
                            et = ""
                            if (peek_kind() == "id") { et = peek_val(); advance() }
                            if (et in struct_names) { field_sz = ne * struct_size[et]; struct_field_elem[sname ":" fname_f] = et }
                            else if (et == "i8"  || et == "u8")  field_sz = ne * 1
                            else if (et == "i32" || et == "u32") field_sz = ne * 4
                            else if (et == "i16" || et == "u16") field_sz = ne * 2
                            else field_sz = ne * 8
                            struct_field_is_array[sname ":" fname_f] = 1
                        } else if (peek_kind() == "id" && tk_kind[POS+1] == "]") {
                            cn = peek_val(); advance()
                            if (peek_kind() == "]") advance()
                            ne = (cn in const_val) ? (const_val[cn] + 0) : 1
                            et = ""
                            if (peek_kind() == "id") { et = peek_val(); advance() }
                            if (et in struct_names) { field_sz = ne * struct_size[et]; struct_field_elem[sname ":" fname_f] = et }
                            else if (et == "i8"  || et == "u8")  field_sz = ne * 1
                            else if (et == "i32" || et == "u32") field_sz = ne * 4
                            else if (et == "i16" || et == "u16") field_sz = ne * 2
                            else field_sz = ne * 8
                            struct_field_is_array[sname ":" fname_f] = 1
                        } else {
                            # []type = pointer/slice = 8 bytes
                            if (peek_kind() == "]") advance()
                            if (peek_kind() == "id") advance()
                        }
                    } else {
                        # Simple type: skip until next field or end of struct
                        while (peek_kind() != "}" && peek_kind() != "eof" && \
                               !(peek_kind() == "id" && tk_kind[POS+1] == ":")) {
                            advance()
                        }
                    }
                    offset += field_sz
                } else {
                    advance()
                }
            }
            if (peek_kind() == "}") { advance(); depth-- }
            struct_size[sname] = offset
            struct_names[sname] = 1
        } else if (depth == 0 && peek_kind() == "kw" && peek_val() == "fn") {
            # Record function return type for LAST_TYPE tracking after calls
            advance()
            if (peek_kind() == "id") { fname_f = peek_val(); advance() }
            else { advance(); continue }
            if (peek_kind() == "(") {   # skip parameter list
                advance(); ne = 1
                while (ne > 0 && peek_kind() != "eof") {
                    if (peek_kind() == "(") ne++
                    else if (peek_kind() == ")") ne--
                    advance()
                }
            }
            if (peek_kind() == "-") {   # look for -> ReturnType
                advance()
                if (peek_kind() == ">") {
                    advance()
                    if (peek_kind() == "&") advance()
                    if (peek_kind() == "[") { advance(); if (peek_kind() == "]") advance() }
                    if (peek_kind() == "id") fn_return_type[fname_f] = peek_val()
                }
            }
            # no advance here -- outer loop will handle { body }
        } else if (depth == 0 && peek_kind() == "kw" && peek_val() == "let") {
            # Top-level global variable
            advance()
            if (peek_kind() != "id") { continue }
            gname = peek_val(); advance()
            global_vars[gname] = 1
            global_off[gname] = GLOBAL_SIZE
            GLOBAL_SIZE += 8
            # skip rest of declaration
            while (peek_kind() != "eof" && peek_kind() != "kw" && \
                   peek_kind() != "fn" && peek_kind() != "struct" && \
                   peek_kind() != "const") {
                if (peek_kind() == "{") depth++
                else if (peek_kind() == "}") { depth--; if (depth < 0) { depth=0; break } }
                advance()
            }
        } else {
            if (peek_kind() == "{") depth++
            else if (peek_kind() == "}") { if (depth > 0) depth-- }
            advance()
        }
    }
    POS = saved_pos
}

# ─── Find struct that contains a field ───────────────────────────────
function find_struct_with_field(fname_f,    sn, key) {
    for (sn in struct_names) {
        key = sn ":" fname_f
        if (key in struct_field_off) return sn
    }
    return ""
}

# ─── Find field offset (search all structs if type unknown) ───────────
function find_field_off(fname_f, type_hint,    key, sn) {
    if (type_hint != "") {
        key = type_hint ":" fname_f
        if (key in struct_field_off) return struct_field_off[key]
    }
    for (sn in struct_names) {
        key = sn ":" fname_f
        if (key in struct_field_off) return struct_field_off[key]
    }
    return -1
}

# ─── x86-64 Code Generator (minimal, ARM64 host) ─────────────────────
function x86_parse_expr() { x86_parse_primary() }

function x86_parse_primary(    kind, val, name, nargs) {
    kind = peek_kind(); val = peek_val()
    if (kind == "int") { advance(); emit("  movq $" val ", %rax"); return }
    if (kind == "str") {
        advance(); NSTR++; str_val[NSTR] = val
        emit("  leaq str_" NSTR "(%rip), %rax"); return
    }
    if (kind == "kw" && val == "true")  { advance(); emit("  movq $1, %rax"); return }
    if (kind == "kw" && val == "false") { advance(); emit("  movq $0, %rax"); return }
    if (kind == "kw" && val == "null")  { advance(); emit("  movq $0, %rax"); return }
    if (kind == "(") { advance(); x86_parse_expr(); expect(")"); return }
    if (kind == "id" || kind == "kw") {
        name = val; advance()
        if (peek_kind() == "(") {
            advance(); nargs = 0
            if (peek_kind() != ")") {
                x86_parse_expr(); nargs++; emit("  pushq %rax")
                while (peek_kind() == ",") { advance(); x86_parse_expr(); nargs++; emit("  pushq %rax") }
            }
            expect(")")
            if (nargs >= 6) emit("  popq %r9")
            if (nargs >= 5) emit("  popq %r8")
            if (nargs >= 4) emit("  popq %rcx")
            if (nargs >= 3) emit("  popq %rdx")
            if (nargs >= 2) emit("  popq %rsi")
            if (nargs >= 1) emit("  popq %rdi")
            emit("  callq _" name); return
        }
        # Skip struct literal { ... }
        if (peek_kind() == "{") {
            advance()
            while (peek_kind() != "}" && peek_kind() != "eof") advance()
            if (peek_kind() == "}") advance()
            emit("  movq $0, %rax"); return
        }
        if (name in const_val) { emit("  movq $" const_val[name] ", %rax"); return }
        emit("  movq $0, %rax"); return
    }
    advance(); emit("  movq $0, %rax")
}

function x86_gen_stmt(    kind, val, name) {
    kind = peek_kind(); val = peek_val()
    if (kind == "kw" && val == "let") {
        advance(); name = peek_val(); advance()
        if (peek_kind() == ":") { advance(); while (peek_kind() != "=" && peek_kind() != "eof") advance() }
        expect("="); x86_parse_expr()
        return
    }
    if (kind == "kw" && val == "ret") {
        advance()
        if (peek_kind() != "}" && peek_kind() != "eof") x86_parse_expr()
        emit("  retq"); return
    }
    if (kind == "kw" && val == "if") {
        advance(); x86_parse_expr()
        expect("{")
        while (peek_kind() != "}" && peek_kind() != "eof") x86_gen_stmt()
        expect("}")
        if (peek_kind() == "kw" && peek_val() == "else") {
            advance(); expect("{")
            while (peek_kind() != "}" && peek_kind() != "eof") x86_gen_stmt()
            expect("}")
        }
        return
    }
    if (kind == "kw" && val == "loop") {
        advance()
        if (peek_kind() == "kw" && peek_val() == "in") advance()
        if (peek_kind() != "{") x86_parse_expr()
        expect("{")
        while (peek_kind() != "}" && peek_kind() != "eof") x86_gen_stmt()
        expect("}"); return
    }
    if (kind == "kw" && val == "match") {
        advance(); x86_parse_expr(); expect("{")
        while (peek_kind() != "}" && peek_kind() != "eof") {
            while (peek_kind() != "=>" && peek_kind() != "}" && peek_kind() != "eof") advance()
            if (peek_kind() == "=>") advance()
            if (peek_kind() == "{") {
                advance()
                while (peek_kind() != "}" && peek_kind() != "eof") x86_gen_stmt()
                expect("}")
            }
        }
        expect("}"); return
    }
    if (kind == "kw" && (val == "break" || val == "continue")) { advance(); return }
    x86_parse_expr()
}

function x86_gen_function(    fname, label, nparams, i, pname) {
    expect_kw("fn"); fname = peek_val(); expect("id"); expect("(")
    nparams = 0; delete env; SLOT = 1
    if (peek_kind() != ")") {
        nparams++; pname = peek_val(); expect("id"); expect(":")
        while (peek_kind() != "," && peek_kind() != ")") advance()
        SLOT++; env[pname] = SLOT * 8
        while (peek_kind() == ",") {
            advance(); nparams++; pname = peek_val(); expect("id"); expect(":")
            while (peek_kind() != "," && peek_kind() != ")") advance()
            SLOT++; env[pname] = SLOT * 8
        }
    }
    expect(")")
    if (peek_kind() == "->") { advance(); while (peek_kind() != "{") advance() }
    label = (fname == "main") ? "_main" : ("_" fname)
    emit(label ":"); emit("  pushq %rbp"); emit("  movq %rsp, %rbp")
    expect("{")
    while (peek_kind() != "}") x86_gen_stmt()
    expect("}")
    emit("  movq $0, %rax"); emit("  popq %rbp"); emit("  retq"); emit("")
}

# ─── ARM64 Code Generator ─────────────────────────────────────────────

function arm64_parse_expr()                { arm64_parse_logical() }

function arm64_parse_logical(    op) {
    arm64_parse_comparison()
    while ((peek_kind() == "kw" && (peek_val() == "and" || peek_val() == "or")) || \
            peek_kind() == "&&" || peek_kind() == "||") {
        op = peek_val(); advance()
        emit("  str x0, [sp, #-16]!")
        arm64_parse_comparison()
        emit("  ldr x1, [sp], #16")
        if (op == "and" || op == "&&") emit("  and x0, x1, x0")
        else                           emit("  orr x0, x1, x0")
    }
}

function arm64_parse_comparison(    op, lbl, cc) {
    arm64_parse_additive()
    while (peek_kind() == "==" || peek_kind() == "!=" || \
           peek_kind() == "<"  || peek_kind() == "<=" || \
           peek_kind() == ">"  || peek_kind() == ">=") {
        op = peek_val(); advance()
        emit("  str x0, [sp, #-16]!")
        arm64_parse_additive()
        emit("  ldr x1, [sp], #16")
        emit("  cmp x1, x0")
        if      (op == "==") cc = "eq"
        else if (op == "!=") cc = "ne"
        else if (op == "<")  cc = "lt"
        else if (op == "<=") cc = "le"
        else if (op == ">")  cc = "gt"
        else                 cc = "ge"
        emit("  cset x0, " cc)
    }
}

function arm64_parse_additive(    op) {
    arm64_parse_multiplicative()
    while (peek_kind() == "+" || peek_kind() == "-" || \
           peek_kind() == ">>" || peek_kind() == "<<" || \
           (peek_kind() == "kw" && (peek_val() == "xor")) || \
           peek_kind() == "^" || peek_kind() == "|") {
        op = peek_val(); advance()
        emit("  str x0, [sp, #-16]!")
        arm64_parse_multiplicative()
        emit("  ldr x1, [sp], #16")
        if      (op == "+")   emit("  add x0, x1, x0")
        else if (op == "-")   emit("  sub x0, x1, x0")
        else if (op == ">>")  emit("  lsr x0, x1, x0")
        else if (op == "<<")  emit("  lsl x0, x1, x0")
        else if (op == "xor" || op == "^") emit("  eor x0, x1, x0")
        else if (op == "|")   emit("  orr x0, x1, x0")
    }
}

function arm64_parse_multiplicative(    op) {
    arm64_parse_unary()
    while (peek_kind() == "*" || peek_kind() == "/" || peek_kind() == "%" || peek_kind() == "&" || \
           (peek_kind() == "id" && peek_val() == "mod")) {
        op = peek_val(); advance()
        emit("  str x0, [sp, #-16]!")
        arm64_parse_unary()
        emit("  ldr x1, [sp], #16")
        if (op == "*")        { emit("  mul x0, x1, x0") }
        else if (op == "/")   { emit("  sdiv x0, x1, x0") }
        else if (op == "%" || op == "mod") { emit("  sdiv x2, x1, x0"); emit("  msub x0, x2, x0, x1") }
        else if (op == "&")   { emit("  and x0, x1, x0") }
    }
}

function arm64_parse_unary() {
    if (peek_kind() == "-") {
        advance(); arm64_parse_unary(); emit("  neg x0, x0"); return
    }
    if (peek_kind() == "kw" && peek_val() == "not") {
        advance(); arm64_parse_unary()
        emit("  cmp x0, #0"); emit("  cset x0, eq"); return
    }
    if (peek_kind() == "!") {
        advance(); arm64_parse_unary()
        emit("  cmp x0, #0"); emit("  cset x0, eq"); return
    }
    if (peek_kind() == "&") {
        advance(); arm64_parse_postfix(); return
    }
    if (peek_kind() == "*") {
        advance(); arm64_parse_unary()
        emit("  ldr x0, [x0]"); return
    }
    arm64_parse_postfix()
}

function arm64_parse_postfix(    fname_f, foff, nargs, saved_lt) {
    arm64_parse_primary()
    while (1) {
        # Namespace access: Type::method(args)
        if (peek_kind() == ":" && tk_kind[POS+1] == ":") {
            saved_lt = LAST_TYPE  # save before arg parsing modifies it
            advance(); advance()  # consume ::
            fname_f = peek_val(); advance()  # method name
            if (peek_kind() == "(") {
                advance()  # (
                nargs = 0
                if (peek_kind() != ")") {
                    arm64_parse_expr(); nargs++; emit("  str x0, [sp, #-16]!")
                    while (peek_kind() == ",") {
                        advance(); arm64_parse_expr(); nargs++; emit("  str x0, [sp, #-16]!")
                    }
                }
                expect(")")
                if (nargs >= 8) emit("  ldr x7, [sp], #16")
                if (nargs >= 7) emit("  ldr x6, [sp], #16")
                if (nargs >= 6) emit("  ldr x5, [sp], #16")
                if (nargs >= 5) emit("  ldr x4, [sp], #16")
                if (nargs >= 4) emit("  ldr x3, [sp], #16")
                if (nargs >= 3) emit("  ldr x2, [sp], #16")
                if (nargs >= 2) emit("  ldr x1, [sp], #16")
                if (nargs >= 1) emit("  ldr x0, [sp], #16")
                # Use saved type prefix (not modified-by-args LAST_TYPE)
                emit("  bl _" saved_lt "__" fname_f)
                LAST_TYPE = (fname_f in fn_return_type) ? fn_return_type[fname_f] : ""
            } else {
                emit("  mov x0, #0")
                LAST_TYPE = ""
            }
            continue
        }
        # Field access or method call: .name or .name(args)
        if (peek_kind() == ".") {
            if (tk_kind[POS+1] == ".") break  # .. range separator
            saved_lt = LAST_TYPE  # save before arg parsing modifies it
            advance()  # consume .
            fname_f = peek_val(); advance()
            if (peek_kind() == "(") {
                # Method call: receiver in x0, push as first arg
                advance()  # (
                emit("  str x0, [sp, #-16]!")
                nargs = 1
                if (peek_kind() != ")") {
                    arm64_parse_expr(); nargs++; emit("  str x0, [sp, #-16]!")
                    while (peek_kind() == ",") {
                        advance(); arm64_parse_expr(); nargs++; emit("  str x0, [sp, #-16]!")
                    }
                }
                expect(")")
                if (nargs >= 8) emit("  ldr x7, [sp], #16")
                if (nargs >= 7) emit("  ldr x6, [sp], #16")
                if (nargs >= 6) emit("  ldr x5, [sp], #16")
                if (nargs >= 5) emit("  ldr x4, [sp], #16")
                if (nargs >= 4) emit("  ldr x3, [sp], #16")
                if (nargs >= 3) emit("  ldr x2, [sp], #16")
                if (nargs >= 2) emit("  ldr x1, [sp], #16")
                if (nargs >= 1) emit("  ldr x0, [sp], #16")
                # Use saved type prefix (not modified-by-args LAST_TYPE)
                if (saved_lt != "") {
                    emit("  bl _" saved_lt "__" fname_f)
                } else {
                    emit("  bl _" fname_f)
                }
                LAST_TYPE = (fname_f in fn_return_type) ? fn_return_type[fname_f] : ""
            } else if (fname_f == "len") {
                # .len on any type: call strlen (strings must be null-terminated)
                emit("  bl _strlen")
                LAST_TYPE = "i64"
            } else {
                # Field read — inline array fields yield the field address, not a loaded pointer
                _flt = LAST_TYPE
                foff = find_field_off(fname_f, _flt)
                _fkey = (_flt != "" && (_flt ":" fname_f) in struct_field_is_array) ? (_flt ":" fname_f) : \
                        (fname_f in struct_field_is_array ? fname_f : "")
                _is_arr = (_flt ":" fname_f) in struct_field_is_array
                if (!_is_arr) {
                    for (_asn in struct_names) {
                        if ((_asn ":" fname_f) in struct_field_is_array) { _is_arr = 1; break }
                    }
                }
                if (foff >= 0) {
                    if (_is_arr) {
                        # Inline array field: result is address of field, not a load
                        if (foff == 0) { } # x0 already points to the field
                        else if (foff <= 4095) emit("  add x0, x0, #" foff)
                        else { emit("  mov x9, #" foff); emit("  add x0, x0, x9") }
                    } else {
                        if (foff <= 32760) emit("  ldr x0, [x0, #" foff "]")
                        else { emit("  mov x9, #" foff); emit("  ldr x0, [x0, x9]") }
                    }
                }
                LAST_TYPE = ""
            }
        # Array indexing: [idx] or [start..end]
        } else if (peek_kind() == "[") {
            advance()  # [
            if (peek_kind() == "]") { advance(); LAST_TYPE = "ptr"; break }
            saved_lt = LAST_TYPE  # save element type before index eval clobbers it
            emit("  str x0, [sp, #-16]!")  # save base
            arm64_parse_expr()             # idx or start in x0
            if (peek_kind() == "." && tk_kind[POS+1] == ".") {
                # Slice [start..end]: null-terminate at base+end so .len = end-start
                advance(); advance()          # consume ..
                emit("  mov x10, x0")         # save start offset in x10
                if (peek_kind() != "]") {
                    arm64_parse_expr()                    # end in x0
                    emit("  ldr x9, [sp], #16")          # restore base ptr into x9
                    emit("  add x11, x9, x0")            # x11 = base + end
                    emit("  strb wzr, [x11]")            # *(base+end) = '\0'
                    emit("  add x0, x9, x10")            # return base + start
                } else {
                    emit("  ldr x0, [sp], #16")          # restore base ptr
                    emit("  add x0, x0, x10")            # base + start (open-ended)
                }
            } else {
                emit("  mov x1, x0")              # index
                emit("  ldr x0, [sp], #16")       # base
                if (saved_lt == "i8" || saved_lt == "u8" || saved_lt == "str") {
                    emit("  add x0, x0, x1")      # byte address: base + idx
                    emit("  ldrb w0, [x0]")       # 1-byte load, zero-extended
                } else {
                    emit("  lsl x1, x1, #3")      # scale by 8 for i64/ptr
                    emit("  ldr x0, [x0, x1]")    # 8-byte load
                }
            }
            expect("]")
            LAST_TYPE = ""
        } else {
            break
        }
    }
    # as type cast: skip ONE type (modifiers then one base id)
    if (peek_kind() == "kw" && peek_val() == "as") {
        advance()
        while (peek_kind() == "&" || peek_kind() == "[" || peek_kind() == "]" || peek_kind() == "*") advance()
        if (peek_kind() == "id") advance()
    }
}

function arm64_parse_primary(    kind, val, name, nargs, idx, lo, hi, sname, base_off, n_slots, foff, fname_f) {
    kind = peek_kind(); val = peek_val()

    if (kind == "int") {
        advance()
        LAST_TYPE = "i64"
        emit_i64_const("x0", val)
        # skip type suffix (i64, i32, u32, etc.) but NOT arbitrary identifiers
        if (peek_kind() == "id") {
            sv = peek_val()
            if (sv == "i64" || sv == "i32" || sv == "i8" || sv == "u64" || sv == "u32" || sv == "u8" || sv == "f64" || sv == "f32") advance()
        }
        return
    }
    if (kind == "str") {
        advance(); NSTR++; str_val[NSTR] = val
        LAST_TYPE = "str"
        emit("  adrp x0, str_" NSTR "@PAGE")
        emit("  add x0, x0, str_" NSTR "@PAGEOFF")
        return
    }
    if (kind == "kw" && val == "true")  { advance(); emit("  mov x0, #1"); LAST_TYPE = "i64"; return }
    if (kind == "kw" && val == "false") { advance(); emit("  mov x0, #0"); LAST_TYPE = "i64"; return }
    if (kind == "kw" && val == "null")  { advance(); emit("  mov x0, #0"); LAST_TYPE = "ptr"; return }

    # fn_addr(name)
    if (kind == "id" && val == "fn_addr") {
        advance(); expect("(")
        name = peek_val(); advance()
        expect(")")
        LAST_TYPE = "fn"
        emit("  adrp x0, _" name "@PAGE")
        emit("  add x0, x0, _" name "@PAGEOFF")
        return
    }

    # call_fn(fn_ptr, arg) - call a function pointer with one argument
    if (kind == "id" && val == "call_fn") {
        advance(); expect("(")
        arm64_parse_expr(); emit("  str x0, [sp, #-16]!")  # push fn_ptr
        expect(",")
        arm64_parse_expr(); emit("  str x0, [sp, #-16]!")  # push arg
        expect(")")
        emit("  ldr x0, [sp], #16")   # pop arg -> x0 (first arg to called fn)
        emit("  ldr x9, [sp], #16")   # pop fn_ptr -> x9
        emit("  blr x9")              # call fn_ptr(arg)
        LAST_TYPE = ""; return
    }

    # Closure expression: |params| { body } - skip, emit 0
    if (kind == "|") {
        advance()  # consume |
        while (peek_kind() != "|" && peek_kind() != "eof") advance()  # skip params
        if (peek_kind() == "|") advance()  # consume closing |
        if (peek_kind() == "{") {
            idx = 1; advance()  # consume {
            while (idx > 0 && peek_kind() != "eof") {
                if (peek_kind() == "{") idx++
                else if (peek_kind() == "}") idx--
                advance()
            }
        }
        emit("  mov x0, #0"); LAST_TYPE = "ptr"; return
    }

    # syscall(...)
    if (kind == "kw" && val == "syscall") {
        advance(); expect("(")
        nargs = 0
        arm64_parse_expr(); nargs++; emit("  str x0, [sp, #-16]!")
        while (peek_kind() == ",") { advance(); arm64_parse_expr(); nargs++; emit("  str x0, [sp, #-16]!") }
        expect(")")
        if (nargs >= 7) emit("  ldr x5, [sp], #16")
        if (nargs >= 6) emit("  ldr x4, [sp], #16")
        if (nargs >= 5) emit("  ldr x3, [sp], #16")
        if (nargs >= 4) emit("  ldr x2, [sp], #16")
        if (nargs >= 3) emit("  ldr x1, [sp], #16")
        if (nargs >= 2) emit("  ldr x0, [sp], #16")
        if (nargs >= 1) emit("  ldr x16, [sp], #16")
        emit("  svc #0x80")
        _svc_ok = new_label()
        emit("  b.cc " _svc_ok)
        emit("  neg x0, x0")
        emit(_svc_ok ":")
        LAST_TYPE = "i64"; return
    }

    # Parenthesized
    if (kind == "(") { advance(); arm64_parse_expr(); expect(")"); return }

    # Fixed array: [N]type or [CONST]type
    if (kind == "[") {
        advance()
        if (peek_kind() == "]") {
            advance()
            if (peek_kind() == "id") advance()
            emit("  mov x0, #0"); LAST_TYPE = "ptr"; return
        }
        n_slots = 0
        if (peek_kind() == "int") {
            n_slots = int((peek_val() + 0 + 7) / 8) + 1
            advance()
        } else if (peek_kind() == "id" && (peek_val() in const_val)) {
            n_slots = int((const_val[peek_val()] + 0 + 7) / 8) + 1
            advance()
        }
        if (n_slots > 0) {
            if (peek_kind() == "]") advance()
            if (peek_kind() == "id") advance()  # skip type name
            base_off = (SLOT + 1) * 8; SLOT += n_slots
            # Zero-initialize: use register-indirect for large offsets
            for (idx = 0; idx < n_slots; idx++) {
                off_now = base_off + idx * 8
                if (off_now <= 32760) {
                    emit("  str xzr, [x29, #" off_now "]")
                } else {
                    emit("  mov x9, #" off_now)
                    emit("  str xzr, [x29, x9]")
                }
            }
            if (base_off <= 4095) {
                emit("  add x0, x29, #" base_off)
            } else {
                emit("  mov x9, #" base_off)
                emit("  add x0, x29, x9")
            }
            LAST_TYPE = "ptr"; return
        }
        emit("  mov x0, #0"); LAST_TYPE = "ptr"; return
    }

    # Identifier: function call, struct init, const, or variable
    if (kind == "id" || (kind == "kw" && \
        val != "fn"    && val != "let"   && val != "ret"      && \
        val != "if"    && val != "else"  && val != "loop"     && \
        val != "break" && val != "for"   && val != "struct"   && \
        val != "enum"  && val != "const" && val != "impl"     && \
        val != "syscall" && val != "not" && val != "in"       && \
        val != "match" && val != "continue" && val != "null"  && \
        val != "and"   && val != "or"    && val != "xor"      && \
        val != "as")) {
        name = val; advance()

        # Function call
        if (peek_kind() == "(") {
            advance(); nargs = 0
            if (peek_kind() != ")") {
                arm64_parse_expr(); nargs++; emit("  str x0, [sp, #-16]!")
                while (peek_kind() == ",") { advance(); arm64_parse_expr(); nargs++; emit("  str x0, [sp, #-16]!") }
            }
            expect(")")
            if (nargs >= 8) emit("  ldr x7, [sp], #16")
            if (nargs >= 7) emit("  ldr x6, [sp], #16")
            if (nargs >= 6) emit("  ldr x5, [sp], #16")
            if (nargs >= 5) emit("  ldr x4, [sp], #16")
            if (nargs >= 4) emit("  ldr x3, [sp], #16")
            if (nargs >= 3) emit("  ldr x2, [sp], #16")
            if (nargs >= 2) emit("  ldr x1, [sp], #16")
            if (nargs >= 1) emit("  ldr x0, [sp], #16")
            emit("  bl _" name)
            LAST_TYPE = ""; return
        }

        # Const value (check BEFORE struct-init so "CONST { block }" doesnt look like struct init)
        if (name in const_val) {
            LAST_TYPE = "i64"
            emit_i64_const("x0", const_val[name])
            return
        }
        # Struct initialization: TypeName { field: expr, ... } or unknown type { ... }
        # Unknown imported struct init: id { field: val, ... }
        # Only treat as struct if brace content starts with "id :" (field:value pattern)
        if (peek_kind() == "{" && !(name in env) && !(name in struct_names)) {
            if (tk_kind[POS+1] == "id" && tk_kind[POS+2] == ":") {
                # Looks like { field: ... } -- consume as unknown struct, emit 0
                advance()  # consume {
                idx = 1  # depth
                while (idx > 0 && peek_kind() != "eof") {
                    if (peek_kind() == "{") idx++
                    else if (peek_kind() == "}") idx--
                    advance()
                }
                emit("  mov x0, #0"); LAST_TYPE = "ptr"; return
            }
        }
        if (peek_kind() == "{" && (name in struct_names)) {
            sname = name; advance()  # consume {
            n_slots = int((struct_size[sname] + 7) / 8)
            if (n_slots == 0) n_slots = 1
            base_off = (SLOT + 1) * 8; SLOT += n_slots
            for (idx = 0; idx < n_slots; idx++) {
                off_now = base_off + idx * 8
                if (off_now <= 32760) emit("  str xzr, [x29, #" off_now "]")
                else { emit("  mov x9, #" off_now); emit("  str xzr, [x29, x9]") }
            }
            while (peek_kind() != "}" && peek_kind() != "eof") {
                if (peek_kind() == "id" && tk_kind[POS+1] == ":") {
                    fname_f = peek_val(); advance(); advance()
                    arm64_parse_expr()
                    foff = struct_field_off[sname ":" fname_f]
                    off_now = base_off + foff
                    if (off_now <= 32760) emit("  str x0, [x29, #" off_now "]")
                    else { emit("  mov x9, #" off_now); emit("  str x0, [x29, x9]") }
                } else if (peek_kind() == ",") {
                    advance()
                } else {
                    advance()
                }
            }
            if (peek_kind() == "}") advance()
            if (base_off <= 4095) emit("  add x0, x29, #" base_off)
            else { emit("  mov x9, #" base_off); emit("  add x0, x29, x9") }
            LAST_TYPE = sname; return
        }

        # Variable lookup (local, then global, then unknown)
        if (name in env) {
            LAST_TYPE = var_type[name]
            emit("  ldr x0, [x29, #" env[name] "]")
        } else if (name in global_off) {
            LAST_TYPE = (name in var_type) ? var_type[name] : ""
            emit("  adrp x9, _jda_globals@PAGE")
            emit("  add x9, x9, _jda_globals@PAGEOFF")
            emit("  ldr x0, [x9, #" global_off[name] "]")
        } else {
            # Unknown: could be a type name used with ::
            LAST_TYPE = name
            emit("  mov x0, #0  // undef: " name)
        }
        return
    }

    # Unknown: skip and emit 0
    advance()
    emit("  mov x0, #0")
}

# ─── ARM64 Statement Generator ───────────────────────────────────────
function arm64_gen_stmt(    kind, val, name, off, else_lbl, end_lbl, top_lbl, cont_lbl, \
                             idx, saved_loop_end, saved_loop_cont, bind_name, pat, \
                             fname_f, foff, iname, end_off, n_slots, base_off, match_end, \
                             cur_type, elem_sn, stride, _sn, _has_type_ann, _mc_nargs) {
    kind = peek_kind(); val = peek_val()

    # let name [: type] = expr (name can be id or keyword used as variable)
    if (kind == "kw" && val == "let") {
        advance()
        name = peek_val()
        if (peek_kind() == "id" || peek_kind() == "kw") advance()
        else expect("id")
        _has_type_ann = 0
        if (peek_kind() == ":") {
            advance()
            if (peek_kind() == "&") advance()   # skip & prefix for &TypeName
            if (peek_kind() == "[") {           # [N]type or []type annotation — may have no =
                advance()
                _arr_n = 0
                if (peek_kind() == "int") { _arr_n = peek_val()+0; advance() }
                else if (peek_kind() == "id" && (peek_val() in const_val)) { _arr_n = const_val[peek_val()]+0; advance() }
                if (peek_kind() == "]") advance()
                _arr_type = ""
                if (peek_kind() == "id") { _arr_type = peek_val(); var_type[name] = _arr_type; _has_type_ann = 1; advance() }
                if (_arr_n > 0 && peek_kind() != "=") {
                    # let name: [N]type  — stack array, no initializer
                    _arr_slots = int((_arr_n + 7) / 8) + 1
                    _arr_base = (SLOT + 1) * 8; SLOT += _arr_slots
                    for (_arr_i = 0; _arr_i < _arr_slots; _arr_i++) {
                        _arr_off = _arr_base + _arr_i * 8
                        if (_arr_off <= 32760) emit("  str xzr, [x29, #" _arr_off "]")
                        else { emit("  mov x9, #" _arr_off); emit("  str xzr, [x29, x9]") }
                    }
                    if (_arr_base <= 4095) emit("  add x0, x29, #" _arr_base)
                    else { emit("  mov x9, #" _arr_base); emit("  add x0, x29, x9") }
                    SLOT++; off = SLOT * 8; env[name] = off
                    emit("  str x0, [x29, #" off "]")
                    return
                }
                # else fall through to expect("=") below
            } else {
                if (peek_kind() == "id") { var_type[name] = peek_val(); _has_type_ann = 1 }
                while (peek_kind() != "=" && peek_kind() != "eof") advance()
            }
        }
        expect("=")
        LAST_TYPE = ""
        arm64_parse_expr()
        SLOT++; off = SLOT * 8; env[name] = off
        if (!_has_type_ann && LAST_TYPE != "") var_type[name] = LAST_TYPE
        emit("  str x0, [x29, #" off "]")
        return
    }

    # ret [expr]
    if (kind == "kw" && val == "ret") {
        advance()
        if (peek_kind() != "}" && peek_kind() != "eof" && \
            !(peek_kind() == "kw" && (peek_val() == "ret" || peek_val() == "if" || \
              peek_val() == "loop" || peek_val() == "break"))) {
            arm64_parse_expr()
        } else {
            emit("  mov x0, #0")
        }
        emit("  ldp x29, x30, [sp, #0]")
        if (FRAME_SIZE <= 4095) {
            emit("  add sp, sp, #" FRAME_SIZE)
        } else {
            emit_i64_const("x9", FRAME_SIZE "")
            emit("  add sp, sp, x9")
        }
        emit("  ret"); LAST_IS_TERM = 1; return
    }

    # spawn { body } - execute body inline (single-threaded stub)
    if (kind == "id" && val == "spawn") {
        advance()
        if (peek_kind() == "{") {
            advance()
            while (peek_kind() != "}" && peek_kind() != "eof") arm64_gen_stmt()
            if (peek_kind() == "}") advance()
        }
        return
    }

    # if cond { } [else if cond { }]* [else { }]
    if (kind == "kw" && val == "if") {
        advance()
        else_lbl = new_label(); end_lbl = new_label()
        arm64_parse_expr()
        emit("  cbz x0, " else_lbl)
        expect("{")
        LAST_IS_TERM = 0
        while (peek_kind() != "}") arm64_gen_stmt()
        expect("}")
        if (peek_kind() == "kw" && peek_val() == "else") {
            if (!LAST_IS_TERM) emit("  b " end_lbl)
            emit(else_lbl ":")
            advance()
            LAST_IS_TERM = 0
            if (peek_kind() == "kw" && peek_val() == "if") {
                arm64_gen_stmt()  # recurse for else if
            } else {
                expect("{")
                while (peek_kind() != "}") arm64_gen_stmt()
                expect("}")
            }
            emit(end_lbl ":")
        } else {
            if (!LAST_IS_TERM) emit("  b " else_lbl)
            emit(else_lbl ":")
        }
        LAST_IS_TERM = 0
        return
    }

    # loop [id in expr..expr] { } or loop cond { } or loop { }
    if (kind == "kw" && val == "loop") {
        advance()
        saved_loop_end  = LOOP_END
        saved_loop_cont = LOOP_CONTINUE
        top_lbl  = new_label()
        end_lbl  = new_label()
        cont_lbl = top_lbl

        if (peek_kind() == "{") {
            # Infinite loop
            LOOP_END = end_lbl; LOOP_CONTINUE = top_lbl
            emit(top_lbl ":")
            expect("{")
            while (peek_kind() != "}") arm64_gen_stmt()
            expect("}")
            emit("  b " top_lbl)
            emit(end_lbl ":")
            LAST_IS_TERM = 1
        } else if (peek_kind() == "id" && tk_kind[POS+1] == "kw" && tk_val[POS+1] == "in") {
            # Range loop: loop i in lo..hi { }
            iname = peek_val(); advance()
            expect_kw("in")
            arm64_parse_expr()              # lo in x0
            SLOT++; off = SLOT * 8; env[iname] = off
            emit("  str x0, [x29, #" off "]")
            expect("."); expect(".")        # consume ..
            arm64_parse_expr()              # hi in x0
            SLOT++; end_off = SLOT * 8
            emit("  str x0, [x29, #" end_off "]")
            cont_lbl = new_label()
            LOOP_END = end_lbl; LOOP_CONTINUE = cont_lbl
            emit(top_lbl ":")
            emit("  ldr x0, [x29, #" off "]")
            emit("  ldr x1, [x29, #" end_off "]")
            emit("  cmp x0, x1")
            emit("  b.ge " end_lbl)
            expect("{")
            while (peek_kind() != "}") arm64_gen_stmt()
            expect("}")
            emit(cont_lbl ":")
            emit("  ldr x0, [x29, #" off "]")
            emit("  add x0, x0, #1")
            emit("  str x0, [x29, #" off "]")
            emit("  b " top_lbl)
            emit(end_lbl ":")
        } else {
            # Conditional loop
            LOOP_END = end_lbl; LOOP_CONTINUE = top_lbl
            emit(top_lbl ":")
            arm64_parse_expr()
            emit("  cbz x0, " end_lbl)
            expect("{")
            while (peek_kind() != "}") arm64_gen_stmt()
            expect("}")
            emit("  b " top_lbl)
            emit(end_lbl ":")
        }
        LOOP_END = saved_loop_end; LOOP_CONTINUE = saved_loop_cont
        return
    }

    # break
    if (kind == "kw" && val == "break") {
        advance()
        if (LOOP_END != "") emit("  b " LOOP_END)
        return
    }

    # continue
    if (kind == "kw" && val == "continue") {
        advance()
        if (LOOP_CONTINUE != "") emit("  b " LOOP_CONTINUE)
        return
    }

    # assignment to keyword-named variable: match = expr, etc.
    if (kind == "kw" && tk_kind[POS+1] == "=") {
        name = val; advance(); advance()  # consume kw and "="
        arm64_parse_expr()
        if (name in env) emit("  str x0, [x29, #" env[name] "]")
        else if (name in global_off) {
            emit("  adrp x9, _jda_globals@PAGE")
            emit("  add x9, x9, _jda_globals@PAGEOFF")
            emit("  str x0, [x9, #" global_off[name] "]")
        }
        return
    }

    # match expr { pat => { body } ... }
    if (kind == "kw" && val == "match") {
        advance()
        arm64_parse_expr()
        emit("  str x0, [sp, #-16]!")  # save match value
        expect("{")
        match_end = new_label()
        while (peek_kind() != "}" && peek_kind() != "eof") {
            end_lbl = new_label()
            pat = "_"; bind_name = "_"
            if (peek_kind() == "id") {
                pat = peek_val(); advance()
                if (peek_kind() == "(") {
                    advance(); bind_name = peek_val(); advance(); expect(")")
                }
            } else if (peek_kind() == "kw") {
                pat = peek_val(); advance()
                if (peek_kind() == "(") {
                    advance(); bind_name = peek_val(); advance(); expect(")")
                }
            }
            # skip => or ->
            if (peek_kind() == "=>") advance()
            else if (peek_kind() == "-") { advance(); if (peek_kind() == ">") advance() }
            # Pattern condition
            if (pat == "ok" || pat == "some") {
                emit("  ldr x0, [sp]"); emit("  cbz x0, " end_lbl)
            } else if (pat == "err" || pat == "none") {
                emit("  ldr x0, [sp]"); emit("  cbnz x0, " end_lbl)
            }
            if (bind_name != "_" && bind_name != "") {
                emit("  ldr x0, [sp]")
                SLOT++; off = SLOT * 8; env[bind_name] = off
                emit("  str x0, [x29, #" off "]")
            }
            expect("{")
            while (peek_kind() != "}" && peek_kind() != "eof") arm64_gen_stmt()
            expect("}")
            emit("  b " match_end)
            emit(end_lbl ":")
            if (peek_kind() == ",") advance()
        }
        expect("}")
        emit(match_end ":")
        emit("  add sp, sp, #16")
        return
    }

    # print expr (debug)
    if (kind == "kw" && val == "print") {
        advance()
        _print_paren = 0
        if (peek_kind() == "(") { advance(); _print_paren = 1 }
        if (peek_kind() == "str") {
            val = peek_val(); advance()
            if (_print_paren && peek_kind() == ")") advance()
            # Check for {varname} interpolation
            if (index(val, "{") > 0) {
                NEED_PRINT_INT = 1
                _pi_s = val; _pi_pos = 1; _pi_len = length(_pi_s)
                while (_pi_pos <= _pi_len) {
                    _pi_ob = index(substr(_pi_s, _pi_pos), "{")
                    if (_pi_ob == 0) {
                        # rest is literal
                        _pi_seg = substr(_pi_s, _pi_pos)
                        if (length(_pi_seg) > 0) {
                            NSTR++; str_val[NSTR] = _pi_seg; _pi_idx = NSTR
                            emit("  mov x0, #1")
                            emit("  adrp x1, str_" _pi_idx "@PAGE")
                            emit("  add x1, x1, str_" _pi_idx "@PAGEOFF")
                            emit("  mov x2, #str_" _pi_idx "_len")
                            emit("  mov x16, #4"); emit("  svc #0x80")
                        }
                        break
                    }
                    # literal before {
                    if (_pi_ob > 1) {
                        _pi_seg = substr(_pi_s, _pi_pos, _pi_ob - 1)
                        NSTR++; str_val[NSTR] = _pi_seg; _pi_idx = NSTR
                        emit("  mov x0, #1")
                        emit("  adrp x1, str_" _pi_idx "@PAGE")
                        emit("  add x1, x1, str_" _pi_idx "@PAGEOFF")
                        emit("  mov x2, #str_" _pi_idx "_len")
                        emit("  mov x16, #4"); emit("  svc #0x80")
                    }
                    _pi_pos += _pi_ob  # now at {
                    _pi_cb = index(substr(_pi_s, _pi_pos), "}")
                    if (_pi_cb == 0) break
                    _pi_vname = substr(_pi_s, _pi_pos, _pi_cb - 1)
                    _pi_pos += _pi_cb
                    # load variable and call __print_int
                    if (_pi_vname in env) {
                        emit("  ldr x0, [x29, #" env[_pi_vname] "]")
                    } else if (_pi_vname in global_off) {
                        emit("  adrp x9, _jda_globals@PAGE")
                        emit("  add x9, x9, _jda_globals@PAGEOFF")
                        emit("  ldr x0, [x9, #" global_off[_pi_vname] "]")
                    } else if (_pi_vname in const_val) {
                        emit("  mov x0, #" const_val[_pi_vname])
                    } else {
                        emit("  mov x0, #0")
                    }
                    emit("  bl __print_int")
                }
            } else {
                NSTR++; str_val[NSTR] = val; idx = NSTR
                emit("  mov x0, #1")
                emit("  adrp x1, str_" idx "@PAGE")
                emit("  add x1, x1, str_" idx "@PAGEOFF")
                emit("  mov x2, #str_" idx "_len")
                emit("  mov x16, #4"); emit("  svc #0x80")
            }
        } else {
            arm64_parse_expr()
            if (_print_paren && peek_kind() == ")") advance()
        }
        return
    }

    # Assignment: id = expr  or  id.f = expr  or  id.f.g = expr  or  id[i] = expr
    if (kind == "id") {
        name = val

        # Simple assignment: id = expr
        if (tk_kind[POS+1] == "=") {
            advance(); advance()
            arm64_parse_expr()
            if (name in env) emit("  str x0, [x29, #" env[name] "]")
            else if (name in global_off) {
                emit("  adrp x9, _jda_globals@PAGE")
                emit("  add x9, x9, _jda_globals@PAGEOFF")
                emit("  str x0, [x9, #" global_off[name] "]")
            }
            return
        }

        # Field / indexed assignment: id.f1[n].f2... = expr
        if (tk_kind[POS+1] == ".") {
            advance()  # consume id
            # Load base struct ptr into x9
            if (name in env)         emit("  ldr x9, [x29, #" env[name] "]")
            else if (name in global_off) {
                emit("  adrp x9, _jda_globals@PAGE")
                emit("  add x9, x9, _jda_globals@PAGEOFF")
                emit("  ldr x9, [x9, #" global_off[name] "]")
            }
            else                     emit("  mov x9, #0")
            # Traverse dot/index chain; all intermediate fields are treated as
            # inline (add offset without deref) so we stay on the right address.
            cur_type = var_type[name]  # track type through chain
            while (1) {
                if (peek_kind() == "." && tk_kind[POS+1] != ".") {
                    advance()  # consume .
                    fname_f = peek_val(); advance()  # field name
                    foff = find_field_off(fname_f, cur_type)
                    if (peek_kind() == "[") {
                        # .field[idx] -- inline array: add field offset, then idx*stride
                        advance()  # [
                        arm64_parse_expr()  # idx in x0
                        emit("  mov x10, x0")
                        expect("]")
                        # Determine element stride: prefer stored elem type over heuristic
                        stride = 8; elem_sn = ""
                        # Look up element type from prescan: try cur_type first, then search
                        if (cur_type != "" && (cur_type ":" fname_f) in struct_field_elem) {
                            elem_sn = struct_field_elem[cur_type ":" fname_f]
                        } else {
                            for (_sn in struct_names) {
                                if ((_sn ":" fname_f) in struct_field_elem) { elem_sn = struct_field_elem[_sn ":" fname_f]; break }
                            }
                        }
                        if (elem_sn != "") { stride = struct_size[elem_sn]; cur_type = elem_sn }
                        else if (peek_kind() == "." && tk_kind[POS+1] != "." && tk_kind[POS+2] != "") {
                            elem_sn = find_struct_with_field(tk_val[POS+1])
                            if (elem_sn != "") { stride = struct_size[elem_sn]; cur_type = elem_sn }
                        }
                        if (foff >= 0) {
                            if (foff <= 4095) emit("  add x9, x9, #" foff)
                            else { emit("  mov x11, #" foff); emit("  add x9, x9, x11") }
                        }
                        if (stride == 8) {
                            emit("  lsl x10, x10, #3")
                        } else {
                            emit("  mov x11, #" stride)
                            emit("  mul x10, x10, x11")
                        }
                        emit("  add x9, x9, x10")
                        # Continue to next field or =
                    } else if (peek_kind() == "=") {
                        # Final: .field = expr
                        # Save x9 (struct pointer) — expr eval may clobber it via adrp x9 for globals
                        advance()  # =
                        emit("  str x9, [sp, #-16]!")
                        arm64_parse_expr()
                        emit("  ldr x9, [sp], #16")
                        if (foff >= 0) {
                            if (foff <= 32760) emit("  str x0, [x9, #" foff "]")
                            else { emit("  mov x10, #" foff); emit("  str x0, [x9, x10]") }
                        } else emit("  str x0, [x9]")
                        return
                    } else if (peek_kind() == "(") {
                        # Method call statement: obj.fname_f(args)
                        advance()  # consume (
                        emit("  str x9, [sp, #-16]!")  # push receiver
                        _mc_nargs = 1
                        if (peek_kind() != ")") {
                            arm64_parse_expr(); _mc_nargs++; emit("  str x0, [sp, #-16]!")
                            while (peek_kind() == ",") {
                                advance(); arm64_parse_expr(); _mc_nargs++; emit("  str x0, [sp, #-16]!")
                            }
                        }
                        expect(")")
                        if (_mc_nargs >= 8) emit("  ldr x7, [sp], #16")
                        if (_mc_nargs >= 7) emit("  ldr x6, [sp], #16")
                        if (_mc_nargs >= 6) emit("  ldr x5, [sp], #16")
                        if (_mc_nargs >= 5) emit("  ldr x4, [sp], #16")
                        if (_mc_nargs >= 4) emit("  ldr x3, [sp], #16")
                        if (_mc_nargs >= 3) emit("  ldr x2, [sp], #16")
                        if (_mc_nargs >= 2) emit("  ldr x1, [sp], #16")
                        if (_mc_nargs >= 1) emit("  ldr x0, [sp], #16")
                        emit("  bl _" fname_f)
                        return
                    } else {
                        # Intermediate: advance x9 by field offset (inline semantics)
                        if (foff >= 0) {
                            if (foff <= 4095) emit("  add x9, x9, #" foff)
                            else { emit("  mov x10, #" foff); emit("  add x9, x9, x10") }
                        }
                    }
                } else if (peek_kind() == "=") {
                    # Direct: id = val (shouldnt normally reach here but handle it)
                    advance()
                    arm64_parse_expr()
                    emit("  str x0, [x9]")
                    return
                } else {
                    break
                }
            }
            # Fallthrough: expression statement
            arm64_parse_expr()
            return
        }

        # Array element assignment: id[idx] = expr
        if (tk_kind[POS+1] == "[") {
            advance()  # consume id
            advance()  # consume [
            arm64_parse_expr()  # idx in x0
            emit("  str x0, [sp, #-16]!")  # push idx (survives function calls)
            expect("]")
            if (peek_kind() == "=") {
                advance()  # =
                if (name in env) emit("  ldr x0, [x29, #" env[name] "]")
                else if (name in global_off) {
                    emit("  adrp x0, _jda_globals@PAGE")
                    emit("  add x0, x0, _jda_globals@PAGEOFF")
                    emit("  ldr x0, [x0, #" global_off[name] "]")
                }
                else             emit("  mov x0, #0")
                emit("  str x0, [sp, #-16]!")  # push ptr
                arm64_parse_expr()             # RHS → x0
                emit("  ldr x9, [sp], #16")    # restore ptr into x9
                emit("  ldr x10, [sp], #16")   # restore idx into x10
                _elem_type = (name in var_type) ? var_type[name] : ""
                if (_elem_type == "i8" || _elem_type == "u8" || _elem_type == "str") {
                    emit("  add x9, x9, x10")  # byte address: base + idx
                    emit("  strb w0, [x9]")    # 1-byte store
                } else {
                    emit("  lsl x10, x10, #3") # scale index by 8 for i64/ptr
                    emit("  str x0, [x9, x10]") # 8-byte store
                }
                return
            }
            # Not an assignment: discard pushed idx and fall through
            emit("  add sp, sp, #16")
        }
    }

    # Expression statement
    arm64_parse_expr()
}

# ─── ARM64 Function Generator ────────────────────────────────────────
function arm64_gen_function_v2(    fname, label, nparams, i, pname, num_locals, \
                                    body_start, body_end, pnames, ptypes) {
    expect_kw("fn")
    fname = peek_val(); expect("id")
    expect("(")

    nparams = 0
    delete env
    delete var_type
    SLOT = 1

    if (peek_kind() != ")") {
        nparams++
        pname = peek_val(); expect("id")
        expect(":")
        ptypes[nparams] = ""
        if (peek_kind() == "id") ptypes[nparams] = peek_val()
        while (peek_kind() != "," && peek_kind() != ")") advance()
        SLOT++; env[pname] = SLOT * 8; pnames[nparams] = pname
        if (ptypes[nparams] != "") var_type[pname] = ptypes[nparams]

        while (peek_kind() == ",") {
            advance(); nparams++
            pname = peek_val(); expect("id")
            expect(":")
            ptypes[nparams] = ""
            if (peek_kind() == "id") ptypes[nparams] = peek_val()
            while (peek_kind() != "," && peek_kind() != ")") advance()
            SLOT++; env[pname] = SLOT * 8; pnames[nparams] = pname
            if (ptypes[nparams] != "") var_type[pname] = ptypes[nparams]
        }
    }
    expect(")")

    if (peek_kind() == "->") { advance(); while (peek_kind() != "{") advance() }

    body_start = POS
    expect("{")
    body_end = find_matching_brace(POS - 1)
    num_locals = count_locals_in_body(POS, body_end)
    POS = body_start
    expect("{")

    label = (fname == "main") ? "_main" : ("_" fname)
    FRAME_SIZE = (num_locals + nparams + 16) * 8
    FRAME_SIZE = int((FRAME_SIZE + 15) / 16) * 16
    if (FRAME_SIZE < 32) FRAME_SIZE = 32

    emit(label ":")
    # Use mov+sub for large frames (sub immediate limited to 12-bit)
    if (FRAME_SIZE <= 4095) {
        emit("  sub sp, sp, #" FRAME_SIZE)
    } else {
        emit_i64_const("x9", FRAME_SIZE "")
        emit("  sub sp, sp, x9")
    }
    emit("  stp x29, x30, [sp, #0]")
    emit("  mov x29, sp")

    for (i = 1; i <= nparams && i <= 8; i++) {
        emit("  str x" (i-1) ", [x29, #" env[pnames[i]] "]")
    }

    while (peek_kind() != "}") arm64_gen_stmt()
    expect("}")

    emit("  mov x0, #0")
    emit("  ldp x29, x30, [sp, #0]")
    if (FRAME_SIZE <= 4095) {
        emit("  add sp, sp, #" FRAME_SIZE)
    } else {
        emit_i64_const("x9", FRAME_SIZE "")
        emit("  add sp, sp, x9")
    }
    emit("  ret")
    emit("")
}

# ─── Bitwise helpers (awk lacks native bitwise ops) ───────────────────
function and_bits(v, mask,    result, bit, vm, mm) {
    result = 0; bit = 1; vm = int(v); mm = int(mask)
    while (vm > 0 || mm > 0) {
        if ((vm % 2) == 1 && (mm % 2) == 1) result += bit
        vm = int(vm / 2); mm = int(mm / 2); bit *= 2
        if (bit > 1073741824) break
    }
    return result
}
function rshift_16(v) { return int(int(v) / 65536) }

# String-based decimal multiply+add: returns s*m+a as decimal string
# Safe for numbers too large for awk double precision (> 2^53)
function bigmul_add(s, m, a,    q, carry, i, digit, tmp) {
    q = ""; carry = a + 0
    for (i = length(s); i >= 1; i--) {
        digit = substr(s, i, 1) + 0
        tmp = digit * m + carry
        q = (tmp % 10) q
        carry = int(tmp / 10)
    }
    while (carry > 0) { q = (carry % 10) q; carry = int(carry / 10) }
    if (q == "") q = "0"
    return q
}

# String-based decimal division: returns quotient in result[0], remainder in result[1]
# Safe for numbers too large for awk double precision (> 2^53)
function bigdiv(s, d, result,    q, r, i, digit) {
    q = ""; r = 0
    for (i = 1; i <= length(s); i++) {
        r = r * 10 + (substr(s, i, 1) + 0)
        q = q sprintf("%d", int(r / d))
        r = int(r % d)
    }
    sub(/^0+/, "", q); if (q == "") q = "0"
    result[0] = q; result[1] = r
}

# Emit a 64-bit constant using movz + up to 3 movk, using string arithmetic
function emit_i64_const(reg, val_str,    parts, tmp, i) {
    delete parts; delete tmp
    for (i = 0; i < 4; i++) {
        bigdiv(val_str, 65536, tmp)
        parts[i] = tmp[1] + 0
        val_str = tmp[0]
    }
    emit("  mov " reg ", #" parts[0])
    for (i = 1; i < 4; i++) {
        if (parts[i] > 0) emit("  movk " reg ", #" parts[i] ", lsl #" (i*16))
    }
}

# ─── Print-int helper ─────────────────────────────────────────────────
function emit_print_int_helper() {
    emit("__print_int:")
    emit("  stp x29, x30, [sp, #-80]!")
    emit("  mov x29, sp")
    emit("  // x0 = integer to print; build decimal in local buffer")
    emit("  add x9, sp, #72")
    emit("  mov x11, #0")
    emit("  cmp x0, #0")
    emit("  bge .Lpi_pos")
    emit("  mov x11, #1")
    emit("  neg x0, x0")
    emit(".Lpi_pos:")
    emit("  mov x10, #10")
    emit("  cbnz x0, .Lpi_loop")
    emit("  mov x12, #48")
    emit("  strb w12, [x9]")
    emit("  sub x9, x9, #1")
    emit("  b .Lpi_sign")
    emit(".Lpi_loop:")
    emit("  udiv x12, x0, x10")
    emit("  msub x13, x12, x10, x0")
    emit("  mov x0, x12")
    emit("  add x13, x13, #48")
    emit("  strb w13, [x9]")
    emit("  sub x9, x9, #1")
    emit("  cbnz x0, .Lpi_loop")
    emit(".Lpi_sign:")
    emit("  cbz x11, .Lpi_write")
    emit("  mov x12, #45")
    emit("  strb w12, [x9]")
    emit("  sub x9, x9, #1")
    emit(".Lpi_write:")
    emit("  add x9, x9, #1")
    emit("  add x10, sp, #73")
    emit("  sub x2, x10, x9")
    emit("  mov x0, #1")
    emit("  mov x1, x9")
    emit("  mov x16, #4")
    emit("  svc #0x80")
    emit("  ldp x29, x30, [sp], #80")
    emit("  ret")
    emit("")
}

# ─── String data emission ─────────────────────────────────────────────
function emit_string_data(    i, s, j, ch, hex_bytes, byte_count, escaped) {
    if (NSTR == 0) return
    emit(".section __TEXT,__cstring,cstring_literals")
    for (i = 1; i <= NSTR; i++) {
        s = str_val[i]
        emit("str_" i ":")
        hex_bytes = ""; byte_count = 0
        for (j = 1; j <= length(s); j++) {
            ch = substr(s, j, 1)
            if (ch == "\\" && j + 1 <= length(s)) {
                escaped = substr(s, j+1, 1)
                if      (escaped == "n")  { hex_bytes = hex_bytes (hex_bytes == "" ? "" : ",") "0x0a"; byte_count++; j++ }
                else if (escaped == "t")  { hex_bytes = hex_bytes (hex_bytes == "" ? "" : ",") "0x09"; byte_count++; j++ }
                else if (escaped == "\\") { hex_bytes = hex_bytes (hex_bytes == "" ? "" : ",") "0x5c"; byte_count++; j++ }
                else if (escaped == "\"") { hex_bytes = hex_bytes (hex_bytes == "" ? "" : ",") "0x22"; byte_count++; j++ }
                else if (escaped == "r")  { hex_bytes = hex_bytes (hex_bytes == "" ? "" : ",") "0x0d"; byte_count++; j++ }
                else if (escaped == "0")  { hex_bytes = hex_bytes (hex_bytes == "" ? "" : ",") "0x00"; byte_count++; j++ }
                else { hex_bytes = hex_bytes (hex_bytes == "" ? "" : ",") sprintf("0x%02x", _ord(ch)); byte_count++ }
            } else {
                hex_bytes = hex_bytes (hex_bytes == "" ? "" : ",") sprintf("0x%02x", _ord(ch))
                byte_count++
            }
        }
        if (hex_bytes != "") emit("  .byte " hex_bytes ",0x00")
        else                  emit("  .byte 0x00")
        emit("str_" i "_len = " byte_count)
    }
    emit("")
}

function emit_globals(    gn, off) {
    if (GLOBAL_SIZE == 0) return
    emit(".section __DATA,__bss,zerofill")
    emit(".align 3")
    emit("_jda_globals:")
    emit("  .zero " GLOBAL_SIZE)
    emit("")
}
function _ord(c,    i) {
    if (!_ord_init) {
        for (i = 0; i < 256; i++) _ord_table[sprintf("%c", i)] = i
        _ord_init = 1
    }
    return (c in _ord_table) ? _ord_table[c] : 63
}

# ─── Main entry point ─────────────────────────────────────────────────
BEGIN {
    OUT = ""; NSTR = 0; LABEL_COUNT = 0
    SLOT = 0; FRAME_SIZE = 0; LOOP_END = ""; LOOP_CONTINUE = ""; POS = 1
    LAST_TYPE = ""; NEED_PRINT_INT = 0
}

{
    if (NR == 1) SOURCE = $0
    else SOURCE = SOURCE "\n" $0
}

END {
    lex()
    prescan()

    if (ARCH == "x86_64") {
        emit(".section __TEXT,__text,regular,pure_instructions")
        emit(".globl _main"); emit("")
    } else {
        emit(".section __TEXT,__text,regular,pure_instructions")
        emit(".globl _main"); emit(".p2align 2"); emit("")
    }

    POS = 1
    while (peek_kind() != "eof") {
        if (peek_kind() == "kw" && peek_val() == "fn") {
            if (ARCH == "x86_64") x86_gen_function()
            else                  arm64_gen_function_v2()
        } else {
            advance()
        }
    }

    if (NEED_PRINT_INT) emit_print_int_helper()
    emit_string_data()
    emit_globals()
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
