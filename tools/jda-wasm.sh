#!/usr/bin/env python3
"""
jda-wasm — WebAssembly compiler for Jda source files

Compiles Jda source to WebAssembly binary (.wasm) format.
Supports WASI target for CLI programs and browser target for web.

Usage:
  jda-wasm.sh <file.jda>                    Compile to .wasm (WASI target)
  jda-wasm.sh --target browser <file.jda>   Compile for browser (no WASI)
  jda-wasm.sh --wat <file.jda>              Output WAT (text format) only
  jda-wasm.sh --run <file.jda>              Compile and run with wasmtime/node
  jda-wasm.sh --html <file.jda>             Generate HTML playground page
  jda-wasm.sh -o <output> <file.jda>        Specify output file name
"""

import sys
import os
import struct
import subprocess
import tempfile
import re

# ─── WASM Constants ──────────────────────────────────────────────────────────

# Section IDs
SEC_TYPE = 1
SEC_IMPORT = 2
SEC_FUNCTION = 3
SEC_TABLE = 4
SEC_MEMORY = 5
SEC_GLOBAL = 6
SEC_EXPORT = 7
SEC_START = 8
SEC_ELEMENT = 9
SEC_CODE = 10
SEC_DATA = 11

# Value types
I32 = 0x7F
I64 = 0x7E
F32 = 0x7D
F64 = 0x7C
FUNCREF = 0x70
VOID = 0x40

# Opcodes
OP_UNREACHABLE = 0x00
OP_NOP = 0x01
OP_BLOCK = 0x02
OP_LOOP = 0x03
OP_IF = 0x04
OP_ELSE = 0x05
OP_END = 0x0B
OP_BR = 0x0C
OP_BR_IF = 0x0D
OP_RETURN = 0x0F
OP_CALL = 0x10
OP_DROP = 0x1A
OP_LOCAL_GET = 0x20
OP_LOCAL_SET = 0x21
OP_LOCAL_TEE = 0x22
OP_GLOBAL_GET = 0x23
OP_GLOBAL_SET = 0x24
OP_I64_LOAD = 0x29
OP_I64_STORE = 0x37
OP_I32_LOAD = 0x28
OP_I32_STORE = 0x36
OP_I64_CONST = 0x42
OP_I32_CONST = 0x41
OP_I64_EQZ = 0x50
OP_I64_EQ = 0x51
OP_I64_NE = 0x52
OP_I64_LT_S = 0x53
OP_I64_GT_S = 0x55
OP_I64_LE_S = 0x57
OP_I64_GE_S = 0x59
OP_I64_ADD = 0x7C
OP_I64_SUB = 0x7D
OP_I64_MUL = 0x7E
OP_I64_DIV_S = 0x7F
OP_I64_REM_S = 0x81
OP_I64_EXTEND_I32_S = 0xAC
OP_I32_WRAP_I64 = 0xA7

# WASI function names
WASI_FD_WRITE = "fd_write"

# ─── Lexer ───────────────────────────────────────────────────────────────────

class Token:
    def __init__(self, kind, val, line):
        self.kind = kind
        self.val = val
        self.line = line

def lex(src):
    tokens = []
    i = 0
    line = 1
    while i < len(src):
        c = src[i]
        if c == '\n':
            line += 1; i += 1
        elif c in ' \t\r':
            i += 1
        elif c == ';' and i+1 < len(src) and src[i+1] == ';':
            while i < len(src) and src[i] != '\n': i += 1
        elif c == '"':
            j = i + 1
            while j < len(src) and src[j] != '"':
                if src[j] == '\\': j += 1
                j += 1
            tokens.append(Token('str', src[i+1:j], line))
            i = j + 1
        elif c.isdigit():
            j = i
            while j < len(src) and src[j].isdigit(): j += 1
            tokens.append(Token('int', int(src[i:j]), line))
            i = j
        elif c.isalpha() or c == '_':
            j = i
            while j < len(src) and (src[j].isalnum() or src[j] == '_'): j += 1
            word = src[i:j]
            kw = {'fn','let','ret','if','else','loop','break','print','struct',
                   'enum','const','impl','syscall','true','false'}
            tokens.append(Token('kw' if word in kw else 'id', word, line))
            i = j
        elif c in '(){},;:':
            tokens.append(Token(c, c, line)); i += 1
        elif c == '-' and i+1 < len(src) and src[i+1] == '>':
            tokens.append(Token('->', '->', line)); i += 2
        elif c in '=!<>' and i+1 < len(src) and src[i+1] == '=':
            tokens.append(Token(src[i:i+2], src[i:i+2], line)); i += 2
        elif c in '+-*/%<>=!':
            tokens.append(Token(c, c, line)); i += 1
        else:
            i += 1
    tokens.append(Token('eof', '', line))
    return tokens

# ─── Parser ──────────────────────────────────────────────────────────────────

class ASTNode:
    def __init__(self, kind, **kw):
        self.kind = kind
        self.__dict__.update(kw)

def parse(tokens):
    pos = [0]
    def peek(): return tokens[pos[0]]
    def advance():
        t = tokens[pos[0]]; pos[0] += 1; return t
    def expect(k):
        t = advance()
        if t.kind != k: raise SyntaxError(f"expected {k}, got {t.kind} '{t.val}' line {t.line}")
        return t
    def expect_kw(w):
        t = advance()
        if t.kind != 'kw' or t.val != w: raise SyntaxError(f"expected '{w}' line {t.line}")
        return t

    def parse_expr():
        return parse_comparison()
    def parse_comparison():
        left = parse_additive()
        while peek().kind in ('==', '!=', '<', '>', '<=', '>='):
            op = advance().kind; right = parse_additive()
            left = ASTNode('binop', op=op, left=left, right=right)
        return left
    def parse_additive():
        left = parse_multiplicative()
        while peek().kind in ('+', '-'):
            op = advance().kind; right = parse_multiplicative()
            left = ASTNode('binop', op=op, left=left, right=right)
        return left
    def parse_multiplicative():
        left = parse_unary()
        while peek().kind in ('*', '/', '%'):
            op = advance().kind; right = parse_unary()
            left = ASTNode('binop', op=op, left=left, right=right)
        return left
    def parse_unary():
        if peek().kind == '-':
            advance(); expr = parse_primary()
            return ASTNode('binop', op='-', left=ASTNode('int', val=0), right=expr)
        return parse_primary()
    def parse_primary():
        t = peek()
        if t.kind == 'int':
            advance(); return ASTNode('int', val=t.val)
        elif t.kind == 'str':
            advance(); return ASTNode('str', val=t.val)
        elif t.kind == 'kw' and t.val == 'true':
            advance(); return ASTNode('int', val=1)
        elif t.kind == 'kw' and t.val == 'false':
            advance(); return ASTNode('int', val=0)
        elif t.kind == 'kw' and t.val == 'syscall':
            advance(); expect('(')
            args = [parse_expr()]
            while peek().kind == ',': advance(); args.append(parse_expr())
            expect(')'); return ASTNode('syscall', args=args)
        elif t.kind == 'id' or (t.kind == 'kw' and t.val not in (
                'fn','let','ret','if','else','loop','break','print',
                'struct','enum','const','impl')):
            name = advance().val
            if peek().kind == '(':
                advance(); args = []
                if peek().kind != ')':
                    args.append(parse_expr())
                    while peek().kind == ',': advance(); args.append(parse_expr())
                expect(')'); return ASTNode('call', name=name, args=args)
            return ASTNode('var', name=name)
        elif t.kind == '(':
            advance(); e = parse_expr(); expect(')'); return e
        raise SyntaxError(f"unexpected {t.kind} '{t.val}' line {t.line}")

    def parse_stmt():
        t = peek()
        if t.kind == 'kw' and t.val == 'let':
            advance(); name = expect('id').val; expect('=')
            return ASTNode('let', name=name, expr=parse_expr())
        elif t.kind == 'kw' and t.val == 'ret':
            advance(); return ASTNode('ret', expr=parse_expr())
        elif t.kind == 'kw' and t.val == 'if':
            advance(); cond = parse_expr(); expect('{'); body = []
            while peek().kind != '}': body.append(parse_stmt())
            expect('}'); else_body = []
            if peek().kind == 'kw' and peek().val == 'else':
                advance(); expect('{')
                while peek().kind != '}': else_body.append(parse_stmt())
                expect('}')
            return ASTNode('if', cond=cond, body=body, else_body=else_body)
        elif t.kind == 'kw' and t.val == 'loop':
            advance(); cond = parse_expr(); expect('{'); body = []
            while peek().kind != '}': body.append(parse_stmt())
            expect('}'); return ASTNode('loop', cond=cond, body=body)
        elif t.kind == 'kw' and t.val == 'break':
            advance(); return ASTNode('break')
        elif t.kind == 'kw' and t.val == 'print':
            advance(); return ASTNode('print', expr=parse_expr())
        else:
            expr = parse_expr()
            if peek().kind == '=':
                advance(); val = parse_expr()
                return ASTNode('assign', name=expr.name, expr=val)
            return ASTNode('expr', expr=expr)

    def parse_fn():
        expect_kw('fn'); name = expect('id').val; expect('(')
        params = []
        if peek().kind != ')':
            pname = expect('id').val; expect(':')
            while peek().kind not in (',', ')'): advance()
            params.append(pname)
            while peek().kind == ',':
                advance(); pname = expect('id').val; expect(':')
                while peek().kind not in (',', ')'): advance()
                params.append(pname)
        expect(')')
        if peek().kind == '->':
            advance()
            while peek().kind not in ('{'): advance()
        expect('{'); body = []
        while peek().kind != '}': body.append(parse_stmt())
        expect('}'); return ASTNode('fn', name=name, params=params, body=body)

    functions = []
    while peek().kind != 'eof':
        if peek().kind == 'kw' and peek().val == 'fn':
            functions.append(parse_fn())
        else: advance()
    return functions


# ─── LEB128 Encoding ────────────────────────────────────────────────────────

def leb128_u(val):
    """Unsigned LEB128."""
    result = bytearray()
    while True:
        byte = val & 0x7F
        val >>= 7
        if val: byte |= 0x80
        result.append(byte)
        if not val: break
    return bytes(result)

def leb128_s(val):
    """Signed LEB128."""
    result = bytearray()
    while True:
        byte = val & 0x7F
        val >>= 7
        if (val == 0 and not (byte & 0x40)) or (val == -1 and (byte & 0x40)):
            result.append(byte)
            break
        result.append(byte | 0x80)
    return bytes(result)


# ─── WASM Binary Encoder ────────────────────────────────────────────────────

class WasmModule:
    """Builds a WASM binary module."""

    def __init__(self):
        self.types = []         # function type signatures
        self.imports = []       # (module, name, type_idx)
        self.functions = []     # type indices for defined functions
        self.exports = []       # (name, kind, idx)
        self.code = []          # function bodies
        self.data = []          # data segments (offset, bytes)
        self.memory_pages = 2   # initial memory (128KB)
        self.globals = []       # (type, mutable, init_val)

    def add_type(self, params, results):
        """Add function type, return index."""
        sig = (tuple(params), tuple(results))
        for i, t in enumerate(self.types):
            if t == sig: return i
        self.types.append(sig)
        return len(self.types) - 1

    def add_import(self, module, name, type_idx):
        """Add import, return function index."""
        idx = len(self.imports)
        self.imports.append((module, name, type_idx))
        return idx

    def add_function(self, type_idx, body_bytes, locals_list):
        """Add function, return index."""
        idx = len(self.imports) + len(self.functions)
        self.functions.append(type_idx)
        self.code.append((locals_list, body_bytes))
        return idx

    def add_export(self, name, kind, idx):
        self.exports.append((name, kind, idx))

    def add_data(self, offset, data_bytes):
        self.data.append((offset, data_bytes))
        return offset

    def add_global(self, valtype, mutable, init_val):
        idx = len(self.globals)
        self.globals.append((valtype, mutable, init_val))
        return idx

    def encode(self):
        """Encode complete WASM binary."""
        out = bytearray()
        # Magic + version
        out += b'\x00asm'
        out += struct.pack('<I', 1)

        # Type section
        if self.types:
            body = bytearray()
            body += leb128_u(len(self.types))
            for params, results in self.types:
                body += b'\x60'  # func type
                body += leb128_u(len(params))
                for p in params: body += bytes([p])
                body += leb128_u(len(results))
                for r in results: body += bytes([r])
            out += self._section(SEC_TYPE, body)

        # Import section
        if self.imports:
            body = bytearray()
            body += leb128_u(len(self.imports))
            for module, name, type_idx in self.imports:
                body += self._encode_str(module)
                body += self._encode_str(name)
                body += b'\x00'  # func import
                body += leb128_u(type_idx)
            out += self._section(SEC_IMPORT, body)

        # Function section
        if self.functions:
            body = bytearray()
            body += leb128_u(len(self.functions))
            for type_idx in self.functions:
                body += leb128_u(type_idx)
            out += self._section(SEC_FUNCTION, body)

        # Memory section
        body = bytearray()
        body += leb128_u(1)  # 1 memory
        body += b'\x00'      # no max
        body += leb128_u(self.memory_pages)
        out += self._section(SEC_MEMORY, body)

        # Global section
        if self.globals:
            body = bytearray()
            body += leb128_u(len(self.globals))
            for valtype, mutable, init_val in self.globals:
                body += bytes([valtype])
                body += bytes([0x01 if mutable else 0x00])
                body += bytes([OP_I64_CONST]) + leb128_s(init_val) + bytes([OP_END])
            out += self._section(SEC_GLOBAL, body)

        # Export section
        if self.exports:
            body = bytearray()
            body += leb128_u(len(self.exports))
            for name, kind, idx in self.exports:
                body += self._encode_str(name)
                body += bytes([kind])  # 0=func, 1=table, 2=memory, 3=global
                body += leb128_u(idx)
            out += self._section(SEC_EXPORT, body)

        # Code section
        if self.code:
            body = bytearray()
            body += leb128_u(len(self.code))
            for locals_list, func_body in self.code:
                func_bytes = bytearray()
                # Locals
                func_bytes += leb128_u(len(locals_list))
                for count, valtype in locals_list:
                    func_bytes += leb128_u(count)
                    func_bytes += bytes([valtype])
                func_bytes += func_body
                func_bytes += bytes([OP_END])
                body += leb128_u(len(func_bytes))
                body += func_bytes
            out += self._section(SEC_CODE, body)

        # Data section
        if self.data:
            body = bytearray()
            body += leb128_u(len(self.data))
            for offset, data_bytes in self.data:
                body += b'\x00'  # active, memory 0
                body += bytes([OP_I32_CONST]) + leb128_s(offset) + bytes([OP_END])
                body += leb128_u(len(data_bytes))
                body += data_bytes
            out += self._section(SEC_DATA, body)

        return bytes(out)

    def _section(self, sec_id, body):
        return bytes([sec_id]) + leb128_u(len(body)) + body

    def _encode_str(self, s):
        b = s.encode('utf-8')
        return leb128_u(len(b)) + b


# ─── WAT Generator ──────────────────────────────────────────────────────────

class WATGen:
    """Generate WebAssembly Text format."""

    def __init__(self, target='wasi'):
        self.target = target
        self.strings = []       # (offset, bytes, label)
        self.data_offset = 1024  # string data starts here
        self.label_count = 0

    def generate(self, functions):
        lines = []
        lines.append("(module")

        if self.target == 'wasi':
            # WASI imports
            lines.append('  (import "wasi_snapshot_preview1" "fd_write"')
            lines.append('    (func $fd_write (param i32 i32 i32 i32) (result i32)))')
            lines.append('  (import "wasi_snapshot_preview1" "proc_exit"')
            lines.append('    (func $proc_exit (param i32)))')
        else:
            # Browser: import console.log from JS
            lines.append('  (import "env" "print_str"')
            lines.append('    (func $print_str (param i32 i32)))')

        lines.append("  (memory (export \"memory\") 2)")

        # Stack pointer global (grows down from 65536)
        lines.append("  (global $sp (mut i64) (i64.const 65536))")

        # Collect strings first
        self._collect_strings(functions)

        # Generate functions
        for fn in functions:
            self._gen_function(fn, lines, functions)

        # Export _start (WASI) or main
        main_fn = next((f for f in functions if f.name == "main"), None)
        if main_fn:
            if self.target == 'wasi':
                lines.append('  (export "_start" (func $main))')
            else:
                lines.append('  (export "main" (func $main))')

        # Data segments for strings
        for offset, data, label in self.strings:
            hex_str = ''.join(f'\\{b:02x}' for b in data)
            lines.append(f'  (data (i32.const {offset}) "{hex_str}")')

        lines.append(")")
        return '\n'.join(lines)

    def _collect_strings(self, functions):
        """Pre-scan to collect all string literals."""
        for fn in functions:
            self._scan_stmts(fn.body)

    def _scan_stmts(self, stmts):
        for s in stmts:
            if s.kind == 'print' and hasattr(s, 'expr') and s.expr.kind == 'str':
                self._add_string(s.expr.val)
            if hasattr(s, 'body'): self._scan_stmts(s.body)
            if hasattr(s, 'else_body'): self._scan_stmts(s.else_body)

    def _add_string(self, s):
        data = s.replace('\\n', '\n').encode('utf-8')
        # Check for duplicate
        for off, d, lbl in self.strings:
            if d == data: return off
        offset = self.data_offset
        label = f"str_{len(self.strings)}"
        self.strings.append((offset, data, label))
        self.data_offset += len(data) + 8  # pad for iov struct
        return offset

    def _get_string_info(self, s):
        data = s.replace('\\n', '\n').encode('utf-8')
        for off, d, lbl in self.strings:
            if d == data: return off, len(d)
        return 0, 0

    def _gen_function(self, fn, lines, all_functions):
        # Collect locals
        locals_map = {}
        for i, p in enumerate(fn.params):
            locals_map[p] = i
        next_local = [len(fn.params)]

        # Count all let bindings
        extra_locals = self._count_locals(fn.body)

        params = " ".join("(param i64)" for _ in fn.params)
        result = "(result i64)"
        local_decls = " ".join("(local i64)" for _ in range(extra_locals))

        sig = f"  (func ${fn.name} {params} {result} {local_decls}"
        lines.append(sig)

        for stmt in fn.body:
            self._gen_stmt(stmt, lines, locals_map, next_local, all_functions, fn.name)

        # Default return 0
        lines.append("    i64.const 0")
        lines.append("  )")

    def _count_locals(self, stmts):
        count = 0
        for s in stmts:
            if s.kind == 'let': count += 1
            if hasattr(s, 'body'): count += self._count_locals(s.body)
            if hasattr(s, 'else_body'): count += self._count_locals(s.else_body)
        return count

    def _gen_stmt(self, stmt, lines, locals_map, next_local, all_fns, fn_name):
        if stmt.kind == 'let':
            self._gen_expr(stmt.expr, lines, locals_map, all_fns)
            idx = next_local[0]
            next_local[0] += 1
            locals_map[stmt.name] = idx + len([k for k in locals_map])
            # Actually, simpler: track by param count offset
            local_idx = len(locals_map)
            locals_map[stmt.name] = local_idx - 1
            lines.append(f"    local.set {local_idx - 1}")

        elif stmt.kind == 'assign':
            self._gen_expr(stmt.expr, lines, locals_map, all_fns)
            idx = locals_map[stmt.name]
            lines.append(f"    local.set {idx}")

        elif stmt.kind == 'ret':
            self._gen_expr(stmt.expr, lines, locals_map, all_fns)
            lines.append("    return")

        elif stmt.kind == 'if':
            self._gen_expr(stmt.cond, lines, locals_map, all_fns)
            lines.append("    i64.const 0")
            lines.append("    i64.ne")
            if stmt.else_body:
                lines.append("    if (result i64)")
                for s in stmt.body:
                    self._gen_stmt(s, lines, locals_map, next_local, all_fns, fn_name)
                lines.append("    i64.const 0")
                lines.append("    else")
                for s in stmt.else_body:
                    self._gen_stmt(s, lines, locals_map, next_local, all_fns, fn_name)
                lines.append("    i64.const 0")
                lines.append("    end")
                lines.append("    drop")
            else:
                lines.append("    if")
                for s in stmt.body:
                    self._gen_stmt(s, lines, locals_map, next_local, all_fns, fn_name)
                lines.append("    end")

        elif stmt.kind == 'loop':
            lines.append("    block $brk")
            lines.append("    loop $top")
            self._gen_expr(stmt.cond, lines, locals_map, all_fns)
            lines.append("    i64.eqz")
            lines.append("    br_if $brk")
            for s in stmt.body:
                self._gen_stmt(s, lines, locals_map, next_local, all_fns, fn_name)
            lines.append("    br $top")
            lines.append("    end")
            lines.append("    end")

        elif stmt.kind == 'break':
            lines.append("    br $brk")

        elif stmt.kind == 'print':
            if stmt.expr.kind == 'str':
                off, length = self._get_string_info(stmt.expr.val)
                if self.target == 'wasi':
                    # Write iov struct to memory at offset 0
                    # iov_base (i32) at offset 0, iov_len (i32) at offset 4
                    lines.append(f"    ;; print \"{stmt.expr.val}\"")
                    lines.append(f"    i32.const 0")       # iov struct at addr 0
                    lines.append(f"    i32.const {off}")    # iov_base = string offset
                    lines.append(f"    i32.store")
                    lines.append(f"    i32.const 4")        # addr 4
                    lines.append(f"    i32.const {length}") # iov_len
                    lines.append(f"    i32.store")
                    lines.append(f"    i32.const 1")        # fd = stdout
                    lines.append(f"    i32.const 0")        # iovs = addr 0
                    lines.append(f"    i32.const 1")        # iovs_len = 1
                    lines.append(f"    i32.const 8")        # nwritten at addr 8
                    lines.append(f"    call $fd_write")
                    lines.append(f"    drop")
                else:
                    lines.append(f"    i32.const {off}")
                    lines.append(f"    i32.const {length}")
                    lines.append(f"    call $print_str")

        elif stmt.kind == 'expr':
            self._gen_expr(stmt.expr, lines, locals_map, all_fns)
            lines.append("    drop")

    def _gen_expr(self, expr, lines, locals_map, all_fns):
        if expr.kind == 'int':
            lines.append(f"    i64.const {expr.val}")

        elif expr.kind == 'var':
            idx = locals_map[expr.name]
            lines.append(f"    local.get {idx}")

        elif expr.kind == 'binop':
            self._gen_expr(expr.left, lines, locals_map, all_fns)
            self._gen_expr(expr.right, lines, locals_map, all_fns)
            ops = {
                '+': 'i64.add', '-': 'i64.sub', '*': 'i64.mul',
                '/': 'i64.div_s', '%': 'i64.rem_s',
                '==': 'i64.eq', '!=': 'i64.ne',
                '<': 'i64.lt_s', '>': 'i64.gt_s',
                '<=': 'i64.le_s', '>=': 'i64.ge_s',
            }
            op = ops.get(expr.op)
            if op:
                lines.append(f"    {op}")
            # Comparison ops return i32, extend to i64
            if expr.op in ('==', '!=', '<', '>', '<=', '>='):
                lines.append("    i64.extend_i32_s")

        elif expr.kind == 'call':
            for arg in expr.args:
                self._gen_expr(arg, lines, locals_map, all_fns)
            lines.append(f"    call ${expr.name}")

        elif expr.kind == 'str':
            off, length = self._get_string_info(expr.val)
            lines.append(f"    i64.const {off}")

    def _gen_function_fixed(self, fn, lines, all_functions):
        """Generate function with correct local indexing."""
        params = []
        locals_map = {}
        for i, p in enumerate(fn.params):
            locals_map[p] = i
            params.append("(param i64)")

        # Pre-scan for let bindings to assign local indices
        local_count = [len(fn.params)]
        self._assign_locals(fn.body, locals_map, local_count)
        extra = local_count[0] - len(fn.params)

        param_str = " ".join(params)
        local_str = " ".join("(local i64)" for _ in range(extra))

        lines.append(f"  (func ${fn.name} {param_str} (result i64) {local_str}")

        for stmt in fn.body:
            self._gen_stmt_fixed(stmt, lines, locals_map, all_functions)

        lines.append("    i64.const 0")
        lines.append("  )")

    def _assign_locals(self, stmts, locals_map, counter):
        for s in stmts:
            if s.kind == 'let':
                locals_map[s.name] = counter[0]
                counter[0] += 1
            if hasattr(s, 'body'):
                self._assign_locals(s.body, locals_map, counter)
            if hasattr(s, 'else_body'):
                self._assign_locals(s.else_body, locals_map, counter)

    def _gen_stmt_fixed(self, stmt, lines, locals_map, all_fns):
        if stmt.kind == 'let':
            self._gen_expr(stmt.expr, lines, locals_map, all_fns)
            idx = locals_map[stmt.name]
            lines.append(f"    local.set {idx}")
        elif stmt.kind == 'assign':
            self._gen_expr(stmt.expr, lines, locals_map, all_fns)
            idx = locals_map[stmt.name]
            lines.append(f"    local.set {idx}")
        elif stmt.kind == 'ret':
            self._gen_expr(stmt.expr, lines, locals_map, all_fns)
            lines.append("    return")
        elif stmt.kind == 'if':
            self._gen_expr(stmt.cond, lines, locals_map, all_fns)
            lines.append("    i64.const 0")
            lines.append("    i64.ne")
            if stmt.else_body:
                lines.append("    if (result i64)")
                for s in stmt.body:
                    self._gen_stmt_fixed(s, lines, locals_map, all_fns)
                lines.append("    i64.const 0")
                lines.append("    else")
                for s in stmt.else_body:
                    self._gen_stmt_fixed(s, lines, locals_map, all_fns)
                lines.append("    i64.const 0")
                lines.append("    end")
                lines.append("    drop")
            else:
                lines.append("    if")
                for s in stmt.body:
                    self._gen_stmt_fixed(s, lines, locals_map, all_fns)
                lines.append("    end")
        elif stmt.kind == 'loop':
            lines.append("    block $brk")
            lines.append("    loop $top")
            self._gen_expr(stmt.cond, lines, locals_map, all_fns)
            lines.append("    i64.eqz")
            lines.append("    br_if $brk")
            for s in stmt.body:
                self._gen_stmt_fixed(s, lines, locals_map, all_fns)
            lines.append("    br $top")
            lines.append("    end")
            lines.append("    end")
        elif stmt.kind == 'break':
            lines.append("    br $brk")
        elif stmt.kind == 'print':
            if stmt.expr.kind == 'str':
                off, length = self._get_string_info(stmt.expr.val)
                if self.target == 'wasi':
                    lines.append(f"    i32.const 0")
                    lines.append(f"    i32.const {off}")
                    lines.append(f"    i32.store")
                    lines.append(f"    i32.const 4")
                    lines.append(f"    i32.const {length}")
                    lines.append(f"    i32.store")
                    lines.append(f"    i32.const 1")
                    lines.append(f"    i32.const 0")
                    lines.append(f"    i32.const 1")
                    lines.append(f"    i32.const 8")
                    lines.append(f"    call $fd_write")
                    lines.append(f"    drop")
                else:
                    lines.append(f"    i32.const {off}")
                    lines.append(f"    i32.const {length}")
                    lines.append(f"    call $print_str")
        elif stmt.kind == 'expr':
            self._gen_expr(stmt.expr, lines, locals_map, all_fns)
            lines.append("    drop")

    def generate_fixed(self, functions):
        """Generate WAT with correct local handling."""
        lines = []
        lines.append("(module")

        if self.target == 'wasi':
            lines.append('  (import "wasi_snapshot_preview1" "fd_write"')
            lines.append('    (func $fd_write (param i32 i32 i32 i32) (result i32)))')
            lines.append('  (import "wasi_snapshot_preview1" "proc_exit"')
            lines.append('    (func $proc_exit (param i32)))')
        else:
            lines.append('  (import "env" "print_str"')
            lines.append('    (func $print_str (param i32 i32)))')

        lines.append("  (memory (export \"memory\") 2)")

        self._collect_strings(functions)

        for fn in functions:
            self._gen_function_fixed(fn, lines, functions)

        main_fn = next((f for f in functions if f.name == "main"), None)
        if main_fn:
            if self.target == 'wasi':
                lines.append('  (export "_start" (func $main))')
            else:
                lines.append('  (export "main" (func $main))')

        for offset, data, label in self.strings:
            hex_str = ''.join(f'\\{b:02x}' for b in data)
            lines.append(f'  (data (i32.const {offset}) "{hex_str}")')

        lines.append(")")
        return '\n'.join(lines)


# ─── HTML Playground Generator ───────────────────────────────────────────────

PLAYGROUND_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Jda Playground</title>
<style>
:root {{ --bg: #1e1e2e; --fg: #cdd6f4; --accent: #89b4fa; --surface: #313244;
         --code-bg: #181825; --green: #a6e3a1; --red: #f38ba8; }}
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{ font-family: -apple-system, monospace; background: var(--bg); color: var(--fg);
        display: flex; flex-direction: column; height: 100vh; }}
header {{ padding: 1rem 2rem; border-bottom: 1px solid var(--surface); }}
header h1 {{ color: var(--accent); font-size: 1.4rem; }}
.container {{ display: flex; flex: 1; overflow: hidden; }}
.editor, .output {{ flex: 1; display: flex; flex-direction: column; }}
.editor {{ border-right: 1px solid var(--surface); }}
.label {{ padding: 0.5rem 1rem; background: var(--surface); font-size: 0.85rem; }}
textarea {{ flex: 1; background: var(--code-bg); color: var(--fg); border: none;
            padding: 1rem; font-family: 'JetBrains Mono', 'Fira Code', monospace;
            font-size: 0.9rem; resize: none; outline: none; tab-size: 2; }}
#output {{ flex: 1; background: var(--code-bg); color: var(--green); padding: 1rem;
           font-family: monospace; font-size: 0.9rem; overflow-y: auto; white-space: pre-wrap; }}
.toolbar {{ padding: 0.5rem 1rem; background: var(--surface); display: flex; gap: 1rem;
            align-items: center; }}
button {{ background: var(--accent); color: var(--bg); border: none; padding: 0.4rem 1.2rem;
          border-radius: 4px; cursor: pointer; font-weight: bold; font-size: 0.9rem; }}
button:hover {{ opacity: 0.9; }}
.status {{ font-size: 0.85rem; color: var(--fg); }}
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
    <textarea id="source" spellcheck="false">{source}</textarea>
  </div>
  <div class="output">
    <div class="label">Output</div>
    <div id="output"></div>
  </div>
</div>
<script>
{wasm_b64}
const wasmBytes = Uint8Array.from(atob(WASM_BASE64), c => c.charCodeAt(0));

async function runCode() {{
  const output = document.getElementById('output');
  const status = document.getElementById('status');
  output.textContent = '';
  status.textContent = 'Running...';

  try {{
    const decoder = new TextDecoder();
    let outputText = '';

    const importObject = {{
      env: {{
        print_str: (ptr, len) => {{
          const mem = new Uint8Array(instance.exports.memory.buffer);
          const str = decoder.decode(mem.slice(ptr, ptr + len));
          outputText += str;
          output.textContent = outputText;
        }}
      }}
    }};

    const {{ instance }} = await WebAssembly.instantiate(wasmBytes, importObject);
    const result = instance.exports.main();
    if (outputText === '') {{
      output.textContent = `(returned ${{result}})`;
    }}
    status.textContent = `Done (returned ${{result}})`;
  }} catch (e) {{
    output.textContent = 'Error: ' + e.message;
    output.style.color = 'var(--red)';
    status.textContent = 'Error';
  }}
}}
</script>
</body>
</html>"""


# ─── Compile & Run ───────────────────────────────────────────────────────────

def compile_wat_to_wasm(wat_source, output_path):
    """Compile WAT to WASM using wat2wasm or inline encoder."""
    with tempfile.TemporaryDirectory() as tmp:
        wat_path = os.path.join(tmp, "prog.wat")
        with open(wat_path, 'w') as f:
            f.write(wat_source)

        # Try wat2wasm first
        try:
            subprocess.run(
                ['wat2wasm', wat_path, '-o', output_path],
                check=True, capture_output=True, text=True
            )
            return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            pass

        # Try wasm-tools
        try:
            subprocess.run(
                ['wasm-tools', 'parse', wat_path, '-o', output_path],
                check=True, capture_output=True, text=True
            )
            return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            pass

        print("error: no WAT compiler found. Install wabt (wat2wasm) or wasm-tools.", file=sys.stderr)
        return False


def run_wasm(wasm_path, target='wasi'):
    """Run WASM file using available runtime."""
    if target == 'wasi':
        # Try wasmtime
        try:
            result = subprocess.run(
                ['wasmtime', wasm_path],
                capture_output=True, text=True, timeout=30
            )
            print(result.stdout, end='')
            if result.stderr: print(result.stderr, end='', file=sys.stderr)
            return result.returncode
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass

        # Try wasmer
        try:
            result = subprocess.run(
                ['wasmer', wasm_path],
                capture_output=True, text=True, timeout=30
            )
            print(result.stdout, end='')
            if result.stderr: print(result.stderr, end='', file=sys.stderr)
            return result.returncode
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass

        # Try node with WASI
        try:
            node_script = f"""
const fs = require('fs');
const {{ WASI }} = require('wasi');
const wasi = new WASI({{ version: 'preview1' }});
const wasm = fs.readFileSync('{wasm_path}');
WebAssembly.compile(wasm).then(m =>
  WebAssembly.instantiate(m, wasi.getImportObject())
).then(i => wasi.start(i));
"""
            result = subprocess.run(
                ['node', '--experimental-wasi-unstable-preview1', '-e', node_script],
                capture_output=True, text=True, timeout=30
            )
            print(result.stdout, end='')
            return result.returncode
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass

        print("error: no WASM runtime found. Install wasmtime, wasmer, or node.", file=sys.stderr)
        return 1
    return 0


# ─── Main ────────────────────────────────────────────────────────────────────

def main():
    args = sys.argv[1:]

    if not args:
        print("jda-wasm — WebAssembly compiler for Jda")
        print()
        print("Usage:")
        print("  jda-wasm.sh <file.jda>                    Compile to .wasm (WASI)")
        print("  jda-wasm.sh --target browser <file.jda>   Browser target")
        print("  jda-wasm.sh --wat <file.jda>              Output WAT text format")
        print("  jda-wasm.sh --run <file.jda>              Compile and run")
        print("  jda-wasm.sh --html <file.jda>             Generate playground HTML")
        print("  jda-wasm.sh -o <output> <file.jda>        Specify output name")
        sys.exit(1)

    target = 'wasi'
    wat_only = False
    do_run = False
    do_html = False
    output = None
    source = None

    i = 0
    while i < len(args):
        if args[i] == '--target' and i + 1 < len(args):
            target = args[i + 1]; i += 2
        elif args[i] == '--wat':
            wat_only = True; i += 1
        elif args[i] == '--run':
            do_run = True; i += 1
        elif args[i] == '--html':
            do_html = True; target = 'browser'; i += 1
        elif args[i] == '-o' and i + 1 < len(args):
            output = args[i + 1]; i += 2
        else:
            source = args[i]; i += 1

    if not source:
        print("error: no source file specified", file=sys.stderr)
        sys.exit(1)

    with open(source, 'r') as f:
        src = f.read()

    tokens = lex(src)
    functions = parse(tokens)

    basename = os.path.splitext(os.path.basename(source))[0]

    gen = WATGen(target=target)
    wat = gen.generate_fixed(functions)

    if wat_only:
        print(wat)
        sys.exit(0)

    if do_html:
        # Compile to WASM for embedding
        with tempfile.TemporaryDirectory() as tmp:
            wasm_path = os.path.join(tmp, f"{basename}.wasm")
            if not compile_wat_to_wasm(wat, wasm_path):
                # Fall back to serving WAT
                html_out = output or f"{basename}.html"
                with open(html_out, 'w') as f:
                    f.write(PLAYGROUND_HTML.format(
                        source=src.replace('{', '{{').replace('}', '}}'),
                        wasm_b64="const WASM_BASE64 = '';"
                    ))
                print(f"Generated: {html_out} (WAT only, no WASM runtime)")
                sys.exit(0)

            import base64
            with open(wasm_path, 'rb') as f:
                wasm_bytes = f.read()
            b64 = base64.b64encode(wasm_bytes).decode('ascii')

            html_out = output or f"{basename}.html"
            with open(html_out, 'w') as f:
                f.write(PLAYGROUND_HTML.format(
                    source=src.replace('{', '{{').replace('}', '}}'),
                    wasm_b64=f"const WASM_BASE64 = '{b64}';"
                ))
            print(f"Generated: {html_out}")
        sys.exit(0)

    # Compile to WASM
    wasm_out = output or f"{basename}.wasm"
    if not compile_wat_to_wasm(wat, wasm_out):
        # Write WAT as fallback
        wat_out = output or f"{basename}.wat"
        with open(wat_out, 'w') as f:
            f.write(wat)
        print(f"WAT written: {wat_out} (install wabt for binary .wasm)")
        sys.exit(0)

    print(f"Compiled: {wasm_out}")

    if do_run:
        sys.exit(run_wasm(wasm_out, target))

if __name__ == "__main__":
    main()
