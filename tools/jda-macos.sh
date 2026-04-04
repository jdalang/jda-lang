#!/usr/bin/env python3
"""
jda-macos — macOS native compiler for Jda source files

Compiles Jda source to native macOS binaries (Mach-O format).
Supports both x86-64 and ARM64 (Apple Silicon).

Usage:
  jda-macos.sh <file.jda>                    Compile to native macOS binary
  jda-macos.sh --arch arm64 <file.jda>       Compile for ARM64 (default on Apple Silicon)
  jda-macos.sh --arch x86_64 <file.jda>      Compile for x86-64
  jda-macos.sh --universal <file.jda>         Build universal binary (x86-64 + arm64)
  jda-macos.sh --asm <file.jda>              Output assembly only
  jda-macos.sh -o <output> <file.jda>        Specify output binary name
"""

import sys
import os
import struct
import subprocess
import tempfile
import platform
import re

# ─── Mach-O Constants ────────────────────────────────────────────────────────

# Magic numbers
MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xBEBAFECA

# CPU types
CPU_TYPE_X86_64 = 0x01000007
CPU_TYPE_ARM64 = 0x0100000C
CPU_SUBTYPE_ALL = 3
CPU_SUBTYPE_ARM64_ALL = 0

# File types
MH_EXECUTE = 2

# Flags
MH_NOUNDEFS = 0x1
MH_PIE = 0x200000

# Load commands
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x02
LC_DYSYMTAB = 0x0B
LC_MAIN = 0x80000028
LC_BUILD_VERSION = 0x32
LC_CODE_SIGNATURE = 0x1D

# Segment/section constants
VM_PROT_READ = 1
VM_PROT_WRITE = 2
VM_PROT_EXECUTE = 4

S_REGULAR = 0
S_ATTR_PURE_INSTRUCTIONS = 0x80000000
S_ATTR_SOME_INSTRUCTIONS = 0x00000400

# macOS syscall numbers (with 0x2000000 prefix for x86-64, direct for arm64)
MACOS_SYS_EXIT = 1
MACOS_SYS_WRITE = 4

# Platform
PLATFORM_MACOS = 1

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
        if t.kind != k: raise SyntaxError(f"expected {k}, got {t.kind} '{t.val}' at line {t.line}")
        return t
    def expect_kw(w):
        t = advance()
        if t.kind != 'kw' or t.val != w: raise SyntaxError(f"expected '{w}', got '{t.val}' at line {t.line}")
        return t

    def parse_expr():
        return parse_comparison()

    def parse_comparison():
        left = parse_additive()
        while peek().kind in ('==', '!=', '<', '>', '<=', '>='):
            op = advance().kind
            right = parse_additive()
            left = ASTNode('binop', op=op, left=left, right=right)
        return left

    def parse_additive():
        left = parse_multiplicative()
        while peek().kind in ('+', '-'):
            op = advance().kind
            right = parse_multiplicative()
            left = ASTNode('binop', op=op, left=left, right=right)
        return left

    def parse_multiplicative():
        left = parse_unary()
        while peek().kind in ('*', '/', '%'):
            op = advance().kind
            right = parse_unary()
            left = ASTNode('binop', op=op, left=left, right=right)
        return left

    def parse_unary():
        if peek().kind == '-':
            advance()
            expr = parse_primary()
            return ASTNode('binop', op='-', left=ASTNode('int', val=0), right=expr)
        return parse_primary()

    def parse_primary():
        t = peek()
        if t.kind == 'int':
            advance()
            return ASTNode('int', val=t.val)
        elif t.kind == 'str':
            advance()
            return ASTNode('str', val=t.val)
        elif t.kind == 'kw' and t.val == 'true':
            advance()
            return ASTNode('int', val=1)
        elif t.kind == 'kw' and t.val == 'false':
            advance()
            return ASTNode('int', val=0)
        elif t.kind == 'kw' and t.val == 'syscall':
            advance()
            expect('(')
            args = [parse_expr()]
            while peek().kind == ',':
                advance()
                args.append(parse_expr())
            expect(')')
            return ASTNode('syscall', args=args)
        elif t.kind == 'id' or (t.kind == 'kw' and t.val not in ('fn','let','ret','if','else','loop','break','print','struct','enum','const','impl')):
            name = advance().val
            if peek().kind == '(':
                advance()
                args = []
                if peek().kind != ')':
                    args.append(parse_expr())
                    while peek().kind == ',':
                        advance()
                        args.append(parse_expr())
                expect(')')
                return ASTNode('call', name=name, args=args)
            return ASTNode('var', name=name)
        elif t.kind == '(':
            advance()
            e = parse_expr()
            expect(')')
            return e
        raise SyntaxError(f"unexpected token {t.kind} '{t.val}' at line {t.line}")

    def parse_stmt():
        t = peek()
        if t.kind == 'kw' and t.val == 'let':
            advance()
            name = expect('id').val
            expect('=')
            expr = parse_expr()
            return ASTNode('let', name=name, expr=expr)
        elif t.kind == 'kw' and t.val == 'ret':
            advance()
            expr = parse_expr()
            return ASTNode('ret', expr=expr)
        elif t.kind == 'kw' and t.val == 'if':
            advance()
            cond = parse_expr()
            expect('{')
            body = []
            while peek().kind != '}':
                body.append(parse_stmt())
            expect('}')
            else_body = []
            if peek().kind == 'kw' and peek().val == 'else':
                advance()
                expect('{')
                while peek().kind != '}':
                    else_body.append(parse_stmt())
                expect('}')
            return ASTNode('if', cond=cond, body=body, else_body=else_body)
        elif t.kind == 'kw' and t.val == 'loop':
            advance()
            cond = parse_expr()
            expect('{')
            body = []
            while peek().kind != '}':
                body.append(parse_stmt())
            expect('}')
            return ASTNode('loop', cond=cond, body=body)
        elif t.kind == 'kw' and t.val == 'break':
            advance()
            return ASTNode('break')
        elif t.kind == 'kw' and t.val == 'print':
            advance()
            expr = parse_expr()
            return ASTNode('print', expr=expr)
        else:
            expr = parse_expr()
            if peek().kind == '=':
                advance()
                val = parse_expr()
                return ASTNode('assign', name=expr.name, expr=val)
            return ASTNode('expr', expr=expr)

    def parse_fn():
        expect_kw('fn')
        name = expect('id').val
        expect('(')
        params = []
        if peek().kind != ')':
            pname = expect('id').val
            expect(':')
            while peek().kind not in (',', ')'):
                advance()
            params.append(pname)
            while peek().kind == ',':
                advance()
                pname = expect('id').val
                expect(':')
                while peek().kind not in (',', ')'):
                    advance()
                params.append(pname)
        expect(')')
        ret_type = None
        if peek().kind == '->':
            advance()
            while peek().kind not in ('{',):
                advance()
        expect('{')
        body = []
        while peek().kind != '}':
            body.append(parse_stmt())
        expect('}')
        return ASTNode('fn', name=name, params=params, body=body)

    functions = []
    while peek().kind != 'eof':
        if peek().kind == 'kw' and peek().val == 'fn':
            functions.append(parse_fn())
        else:
            advance()
    return functions


# ─── x86-64 macOS Code Generator ────────────────────────────────────────────

class X86_64MacOSGen:
    """Generate x86-64 assembly for macOS (System V AMD64 ABI + macOS syscalls)."""

    def __init__(self):
        self.strings = []
        self.label_count = 0

    def new_label(self):
        self.label_count += 1
        return f".L{self.label_count}"

    def generate(self, functions):
        lines = []
        lines.append(".section __TEXT,__text,regular,pure_instructions")
        lines.append(".globl _main")
        lines.append("")

        for fn in functions:
            label = "_main" if fn.name == "main" else f"_{fn.name}"
            lines.append(f"{label}:")
            lines.append("  pushq %rbp")
            lines.append("  movq %rsp, %rbp")

            # Allocate stack frame
            num_locals = self._count_locals(fn.body) + len(fn.params)
            frame_size = max(((num_locals + 1) * 8 + 15) & ~15, 16)
            lines.append(f"  subq ${frame_size}, %rsp")

            # Store parameters
            param_regs = ['%rdi', '%rsi', '%rdx', '%rcx', '%r8', '%r9']
            env = {}
            for i, p in enumerate(fn.params):
                off = (i + 1) * 8
                env[p] = off
                if i < len(param_regs):
                    lines.append(f"  movq {param_regs[i]}, -{off}(%rbp)")

            self._slot = len(fn.params)
            self._gen_stmts(fn, lines, env, frame_size)

            # Default return 0
            lines.append("  xorl %eax, %eax")
            lines.append(f"  addq ${frame_size}, %rsp")
            lines.append("  popq %rbp")
            lines.append("  retq")
            lines.append("")

        # String data
        if self.strings:
            lines.append(".section __TEXT,__cstring,cstring_literals")
            for i, s in enumerate(self.strings):
                escaped = s.replace('\\n', '\n').encode('utf-8')
                lines.append(f"str_{i}:")
                hex_bytes = ','.join(f'0x{b:02x}' for b in escaped)
                lines.append(f"  .byte {hex_bytes}")
                lines.append(f"str_{i}_len = {len(escaped)}")
            lines.append("")

        return '\n'.join(lines)

    def _count_locals(self, stmts):
        count = 0
        for s in stmts:
            if s.kind == 'let': count += 1
            if hasattr(s, 'body'): count += self._count_locals(s.body)
            if hasattr(s, 'else_body'): count += self._count_locals(s.else_body)
        return count

    def _gen_stmts(self, fn, lines, env, frame_size):
        for stmt in fn.body:
            self._gen_stmt(stmt, lines, env, fn.name, frame_size)

    def _gen_stmt(self, stmt, lines, env, fn_name, frame_size):
        if stmt.kind == 'let':
            self._gen_expr(stmt.expr, lines, env)
            self._slot += 1
            off = self._slot * 8
            env[stmt.name] = off
            lines.append(f"  movq %rax, -{off}(%rbp)")

        elif stmt.kind == 'assign':
            self._gen_expr(stmt.expr, lines, env)
            off = env[stmt.name]
            lines.append(f"  movq %rax, -{off}(%rbp)")

        elif stmt.kind == 'ret':
            self._gen_expr(stmt.expr, lines, env)
            lines.append(f"  addq ${frame_size}, %rsp")
            lines.append("  popq %rbp")
            lines.append("  retq")

        elif stmt.kind == 'if':
            else_label = self.new_label()
            end_label = self.new_label()
            self._gen_expr(stmt.cond, lines, env)
            lines.append("  testq %rax, %rax")
            lines.append(f"  je {else_label}")
            for s in stmt.body:
                self._gen_stmt(s, lines, env, fn_name, frame_size)
            if stmt.else_body:
                lines.append(f"  jmp {end_label}")
            lines.append(f"{else_label}:")
            if stmt.else_body:
                for s in stmt.else_body:
                    self._gen_stmt(s, lines, env, fn_name, frame_size)
                lines.append(f"{end_label}:")

        elif stmt.kind == 'loop':
            top_label = self.new_label()
            end_label = self.new_label()
            self._loop_end = end_label
            lines.append(f"{top_label}:")
            self._gen_expr(stmt.cond, lines, env)
            lines.append("  testq %rax, %rax")
            lines.append(f"  je {end_label}")
            for s in stmt.body:
                self._gen_stmt(s, lines, env, fn_name, frame_size)
            lines.append(f"  jmp {top_label}")
            lines.append(f"{end_label}:")

        elif stmt.kind == 'break':
            lines.append(f"  jmp {self._loop_end}")

        elif stmt.kind == 'print':
            if stmt.expr.kind == 'str':
                idx = len(self.strings)
                self.strings.append(stmt.expr.val)
                lines.append(f"  movq $0x2000004, %rax")  # write syscall
                lines.append(f"  movq $1, %rdi")           # stdout
                lines.append(f"  leaq str_{idx}(%rip), %rsi")
                lines.append(f"  movq $str_{idx}_len, %rdx")
                lines.append("  syscall")
            else:
                self._gen_expr(stmt.expr, lines, env)
                lines.append("  movq %rax, %rdi")
                lines.append("  callq _print_int")

        elif stmt.kind == 'expr':
            self._gen_expr(stmt.expr, lines, env)

    def _gen_expr(self, expr, lines, env):
        if expr.kind == 'int':
            lines.append(f"  movq ${expr.val}, %rax")

        elif expr.kind == 'var':
            off = env[expr.name]
            lines.append(f"  movq -{off}(%rbp), %rax")

        elif expr.kind == 'binop':
            self._gen_expr(expr.right, lines, env)
            lines.append("  pushq %rax")
            self._gen_expr(expr.left, lines, env)
            lines.append("  popq %rcx")
            if expr.op == '+': lines.append("  addq %rcx, %rax")
            elif expr.op == '-': lines.append("  subq %rcx, %rax")
            elif expr.op == '*': lines.append("  imulq %rcx, %rax")
            elif expr.op == '/':
                lines.append("  cqto")
                lines.append("  idivq %rcx")
            elif expr.op == '%':
                lines.append("  cqto")
                lines.append("  idivq %rcx")
                lines.append("  movq %rdx, %rax")
            elif expr.op in ('==', '!=', '<', '>', '<=', '>='):
                lines.append("  cmpq %rcx, %rax")
                cc = {'==': 'sete', '!=': 'setne', '<': 'setl', '>': 'setg',
                       '<=': 'setle', '>=': 'setge'}[expr.op]
                lines.append(f"  {cc} %al")
                lines.append("  movzbq %al, %rax")

        elif expr.kind == 'call':
            param_regs = ['%rdi', '%rsi', '%rdx', '%rcx', '%r8', '%r9']
            # Push args right-to-left, then pop into regs
            for arg in reversed(expr.args):
                self._gen_expr(arg, lines, env)
                lines.append("  pushq %rax")
            for i in range(min(len(expr.args), len(param_regs))):
                lines.append(f"  popq {param_regs[i]}")
            label = f"_{expr.name}"
            lines.append(f"  callq {label}")

        elif expr.kind == 'syscall':
            # macOS x86-64: syscall number in rax (with 0x2000000 prefix)
            # args in rdi, rsi, rdx, r10, r8, r9
            sys_regs = ['%rdi', '%rsi', '%rdx', '%r10', '%r8', '%r9']
            for arg in reversed(expr.args[1:]):
                self._gen_expr(arg, lines, env)
                lines.append("  pushq %rax")
            self._gen_expr(expr.args[0], lines, env)
            lines.append("  addq $0x2000000, %rax")  # macOS syscall prefix
            for i in range(len(expr.args) - 1):
                lines.append(f"  popq {sys_regs[i]}")
            lines.append("  syscall")

        elif expr.kind == 'str':
            idx = len(self.strings)
            self.strings.append(expr.val)
            lines.append(f"  leaq str_{idx}(%rip), %rax")


# ─── ARM64 macOS Code Generator ─────────────────────────────────────────────

class ARM64MacOSGen:
    """Generate ARM64 assembly for macOS (AAPCS64 + macOS syscalls)."""

    def __init__(self):
        self.strings = []
        self.label_count = 0

    def new_label(self):
        self.label_count += 1
        return f".L{self.label_count}"

    def generate(self, functions):
        lines = []
        lines.append(".section __TEXT,__text,regular,pure_instructions")
        lines.append(".globl _main")
        lines.append(".p2align 2")
        lines.append("")

        for fn in functions:
            label = "_main" if fn.name == "main" else f"_{fn.name}"
            lines.append(f"{label}:")

            num_locals = self._count_locals(fn.body) + len(fn.params)
            frame_size = max(((num_locals + 2) * 8 + 15) & ~15, 32)

            lines.append(f"  stp x29, x30, [sp, #-{frame_size}]!")
            lines.append("  mov x29, sp")

            # Store parameters (x0-x7)
            env = {}
            for i, p in enumerate(fn.params):
                off = (i + 1) * 8
                env[p] = off
                lines.append(f"  str x{i}, [x29, #{off}]")

            self._slot = len(fn.params)
            self._gen_stmts(fn, lines, env, frame_size)

            # Default return 0
            lines.append("  mov x0, #0")
            lines.append(f"  ldp x29, x30, [sp], #{frame_size}")
            lines.append("  ret")
            lines.append("")

        # String data
        if self.strings:
            lines.append(".section __TEXT,__cstring,cstring_literals")
            for i, s in enumerate(self.strings):
                escaped = s.replace('\\n', '\n').encode('utf-8')
                lines.append(f"str_{i}:")
                lines.append(f'  .asciz "{s}"')
                lines.append(f"str_{i}_len = {len(escaped)}")
            lines.append("")

        return '\n'.join(lines)

    def _count_locals(self, stmts):
        count = 0
        for s in stmts:
            if s.kind == 'let': count += 1
            if hasattr(s, 'body'): count += self._count_locals(s.body)
            if hasattr(s, 'else_body'): count += self._count_locals(s.else_body)
        return count

    def _gen_stmts(self, fn, lines, env, frame_size):
        for stmt in fn.body:
            self._gen_stmt(stmt, lines, env, fn.name, frame_size)

    def _gen_stmt(self, stmt, lines, env, fn_name, frame_size):
        if stmt.kind == 'let':
            self._gen_expr(stmt.expr, lines, env)
            self._slot += 1
            off = self._slot * 8
            env[stmt.name] = off
            lines.append(f"  str x0, [x29, #{off}]")

        elif stmt.kind == 'assign':
            self._gen_expr(stmt.expr, lines, env)
            off = env[stmt.name]
            lines.append(f"  str x0, [x29, #{off}]")

        elif stmt.kind == 'ret':
            self._gen_expr(stmt.expr, lines, env)
            lines.append(f"  ldp x29, x30, [sp], #{frame_size}")
            lines.append("  ret")

        elif stmt.kind == 'if':
            else_label = self.new_label()
            end_label = self.new_label()
            self._gen_expr(stmt.cond, lines, env)
            lines.append(f"  cbz x0, {else_label}")
            for s in stmt.body:
                self._gen_stmt(s, lines, env, fn_name, frame_size)
            if stmt.else_body:
                lines.append(f"  b {end_label}")
            lines.append(f"{else_label}:")
            if stmt.else_body:
                for s in stmt.else_body:
                    self._gen_stmt(s, lines, env, fn_name, frame_size)
                lines.append(f"{end_label}:")

        elif stmt.kind == 'loop':
            top_label = self.new_label()
            end_label = self.new_label()
            self._loop_end = end_label
            lines.append(f"{top_label}:")
            self._gen_expr(stmt.cond, lines, env)
            lines.append(f"  cbz x0, {end_label}")
            for s in stmt.body:
                self._gen_stmt(s, lines, env, fn_name, frame_size)
            lines.append(f"  b {top_label}")
            lines.append(f"{end_label}:")

        elif stmt.kind == 'break':
            lines.append(f"  b {self._loop_end}")

        elif stmt.kind == 'print':
            if stmt.expr.kind == 'str':
                idx = len(self.strings)
                self.strings.append(stmt.expr.val)
                lines.append(f"  mov x0, #1")              # stdout
                lines.append(f"  adrp x1, str_{idx}@PAGE")
                lines.append(f"  add x1, x1, str_{idx}@PAGEOFF")
                lines.append(f"  mov x2, #str_{idx}_len")
                lines.append(f"  mov x16, #4")              # write syscall
                lines.append("  svc #0x80")                 # macOS ARM64 syscall
            else:
                self._gen_expr(stmt.expr, lines, env)
                lines.append("  bl _print_int")

        elif stmt.kind == 'expr':
            self._gen_expr(stmt.expr, lines, env)

    def _gen_expr(self, expr, lines, env):
        if expr.kind == 'int':
            if expr.val >= 0 and expr.val < 65536:
                lines.append(f"  mov x0, #{expr.val}")
            else:
                lines.append(f"  mov x0, #{expr.val & 0xFFFF}")
                if expr.val > 0xFFFF:
                    lines.append(f"  movk x0, #{(expr.val >> 16) & 0xFFFF}, lsl #16")

        elif expr.kind == 'var':
            off = env[expr.name]
            lines.append(f"  ldr x0, [x29, #{off}]")

        elif expr.kind == 'binop':
            self._gen_expr(expr.left, lines, env)
            lines.append("  str x0, [sp, #-16]!")
            self._gen_expr(expr.right, lines, env)
            lines.append("  mov x1, x0")
            lines.append("  ldr x0, [sp], #16")
            if expr.op == '+': lines.append("  add x0, x0, x1")
            elif expr.op == '-': lines.append("  sub x0, x0, x1")
            elif expr.op == '*': lines.append("  mul x0, x0, x1")
            elif expr.op == '/': lines.append("  sdiv x0, x0, x1")
            elif expr.op == '%':
                lines.append("  sdiv x2, x0, x1")
                lines.append("  msub x0, x2, x1, x0")
            elif expr.op in ('==', '!=', '<', '>', '<=', '>='):
                lines.append("  cmp x0, x1")
                cc = {'==': 'eq', '!=': 'ne', '<': 'lt', '>': 'gt',
                       '<=': 'le', '>=': 'ge'}[expr.op]
                lines.append(f"  cset x0, {cc}")

        elif expr.kind == 'call':
            for i, arg in enumerate(expr.args):
                self._gen_expr(arg, lines, env)
                if i < len(expr.args) - 1:
                    lines.append("  str x0, [sp, #-16]!")
            # Pop args into registers in reverse
            for i in range(len(expr.args) - 2, -1, -1):
                lines.append(f"  ldr x{i}, [sp], #16" if i < len(expr.args) - 1 else "")
            # Last arg is already in x0, move to correct reg
            if len(expr.args) > 1:
                lines.append(f"  mov x{len(expr.args)-1}, x0")
                for i in range(len(expr.args) - 2, -1, -1):
                    lines.append(f"  ldr x{i}, [sp], #16")
            # Simpler approach: push all then pop
            lines.clear()  # Redo with simpler approach

        elif expr.kind == 'syscall':
            # macOS ARM64: syscall number in x16, args in x0-x5, svc #0x80
            pass

        elif expr.kind == 'str':
            idx = len(self.strings)
            self.strings.append(expr.val)
            lines.append(f"  adrp x0, str_{idx}@PAGE")
            lines.append(f"  add x0, x0, str_{idx}@PAGEOFF")

    def _gen_call_args(self, expr, lines, env):
        """Generate function call with proper arg passing."""
        # Push all args to stack, then pop into x0-x7
        for arg in reversed(expr.args):
            self._gen_expr(arg, lines, env)
            lines.append("  str x0, [sp, #-16]!")
        for i in range(len(expr.args)):
            lines.append(f"  ldr x{i}, [sp], #16")
        label = f"_{expr.name}"
        lines.append(f"  bl {label}")


# Rewrite ARM64 gen with cleaner call handling
class ARM64MacOSGen2:
    """Generate ARM64 assembly for macOS (AAPCS64 + macOS syscalls)."""

    def __init__(self):
        self.strings = []
        self.label_count = 0

    def new_label(self):
        self.label_count += 1
        return f".L{self.label_count}"

    def generate(self, functions):
        lines = []
        lines.append(".section __TEXT,__text,regular,pure_instructions")
        lines.append(".globl _main")
        lines.append(".p2align 2")
        lines.append("")

        for fn in functions:
            label = "_main" if fn.name == "main" else f"_{fn.name}"
            lines.append(f"{label}:")

            num_locals = self._count_locals(fn.body) + len(fn.params) + 2  # +2 for x29+x30
            frame_size = max((num_locals * 8 + 15) & ~15, 32)

            lines.append(f"  stp x29, x30, [sp, #-{frame_size}]!")
            lines.append("  mov x29, sp")

            env = {}
            for i, p in enumerate(fn.params):
                off = (i + 2) * 8  # skip saved x29+x30 at offsets 0 and 8
                env[p] = off
                lines.append(f"  str x{i}, [x29, #{off}]")

            self._slot = len(fn.params) + 1  # next slot starts after params+x29/x30
            for stmt in fn.body:
                self._gen_stmt(stmt, lines, env, fn.name, frame_size)

            lines.append("  mov x0, #0")
            lines.append(f"  ldp x29, x30, [sp], #{frame_size}")
            lines.append("  ret")
            lines.append("")

        if self.strings:
            lines.append(".section __TEXT,__cstring,cstring_literals")
            for i, s in enumerate(self.strings):
                escaped = s.replace('\\n', '\n').encode('utf-8')
                lines.append(f"str_{i}:")
                hex_bytes = ','.join(f'0x{b:02x}' for b in escaped)
                lines.append(f"  .byte {hex_bytes}")
                lines.append(f"str_{i}_len = {len(escaped)}")
            lines.append("")

        return '\n'.join(lines)

    def _count_locals(self, stmts):
        count = 0
        for s in stmts:
            if s.kind == 'let': count += 1
            if hasattr(s, 'body'): count += self._count_locals(s.body)
            if hasattr(s, 'else_body'): count += self._count_locals(s.else_body)
        return count

    def _gen_stmt(self, stmt, lines, env, fn_name, frame_size):
        if stmt.kind == 'let':
            self._gen_expr(stmt.expr, lines, env)
            self._slot += 1
            off = self._slot * 8
            env[stmt.name] = off
            lines.append(f"  str x0, [x29, #{off}]")
        elif stmt.kind == 'assign':
            self._gen_expr(stmt.expr, lines, env)
            off = env[stmt.name]
            lines.append(f"  str x0, [x29, #{off}]")
        elif stmt.kind == 'ret':
            self._gen_expr(stmt.expr, lines, env)
            lines.append(f"  ldp x29, x30, [sp], #{frame_size}")
            lines.append("  ret")
        elif stmt.kind == 'if':
            else_label = self.new_label()
            end_label = self.new_label()
            self._gen_expr(stmt.cond, lines, env)
            lines.append(f"  cbz x0, {else_label}")
            for s in stmt.body:
                self._gen_stmt(s, lines, env, fn_name, frame_size)
            if stmt.else_body:
                lines.append(f"  b {end_label}")
            lines.append(f"{else_label}:")
            if stmt.else_body:
                for s in stmt.else_body:
                    self._gen_stmt(s, lines, env, fn_name, frame_size)
                lines.append(f"{end_label}:")
        elif stmt.kind == 'loop':
            top_label = self.new_label()
            end_label = self.new_label()
            self._loop_end = end_label
            lines.append(f"{top_label}:")
            self._gen_expr(stmt.cond, lines, env)
            lines.append(f"  cbz x0, {end_label}")
            for s in stmt.body:
                self._gen_stmt(s, lines, env, fn_name, frame_size)
            lines.append(f"  b {top_label}")
            lines.append(f"{end_label}:")
        elif stmt.kind == 'break':
            lines.append(f"  b {self._loop_end}")
        elif stmt.kind == 'print':
            if stmt.expr.kind == 'str':
                idx = len(self.strings)
                self.strings.append(stmt.expr.val)
                lines.append(f"  mov x0, #1")
                lines.append(f"  adrp x1, str_{idx}@PAGE")
                lines.append(f"  add x1, x1, str_{idx}@PAGEOFF")
                lines.append(f"  mov x2, #str_{idx}_len")
                lines.append(f"  mov x16, #4")
                lines.append("  svc #0x80")
        elif stmt.kind == 'expr':
            self._gen_expr(stmt.expr, lines, env)

    def _gen_expr(self, expr, lines, env):
        if expr.kind == 'int':
            if 0 <= expr.val < 65536:
                lines.append(f"  mov x0, #{expr.val}")
            else:
                lines.append(f"  mov x0, #{expr.val & 0xFFFF}")
                if expr.val > 0xFFFF:
                    lines.append(f"  movk x0, #{(expr.val >> 16) & 0xFFFF}, lsl #16")
        elif expr.kind == 'var':
            off = env[expr.name]
            lines.append(f"  ldr x0, [x29, #{off}]")
        elif expr.kind == 'binop':
            self._gen_expr(expr.left, lines, env)
            lines.append("  str x0, [sp, #-16]!")
            self._gen_expr(expr.right, lines, env)
            lines.append("  mov x1, x0")
            lines.append("  ldr x0, [sp], #16")
            if expr.op == '+': lines.append("  add x0, x0, x1")
            elif expr.op == '-': lines.append("  sub x0, x0, x1")
            elif expr.op == '*': lines.append("  mul x0, x0, x1")
            elif expr.op == '/': lines.append("  sdiv x0, x0, x1")
            elif expr.op == '%':
                lines.append("  sdiv x2, x0, x1")
                lines.append("  msub x0, x2, x1, x0")
            elif expr.op in ('==', '!=', '<', '>', '<=', '>='):
                lines.append("  cmp x0, x1")
                cc = {'==': 'eq', '!=': 'ne', '<': 'lt', '>': 'gt',
                       '<=': 'le', '>=': 'ge'}[expr.op]
                lines.append(f"  cset x0, {cc}")
        elif expr.kind == 'call':
            for arg in reversed(expr.args):
                self._gen_expr(arg, lines, env)
                lines.append("  str x0, [sp, #-16]!")
            for i in range(len(expr.args)):
                lines.append(f"  ldr x{i}, [sp], #16")
            label = f"_{expr.name}"
            lines.append(f"  bl {label}")
        elif expr.kind == 'syscall':
            # macOS ARM64: syscall number in x16, args in x0-x5, svc #0x80
            for arg in reversed(expr.args[1:]):
                self._gen_expr(arg, lines, env)
                lines.append("  str x0, [sp, #-16]!")
            self._gen_expr(expr.args[0], lines, env)
            lines.append("  mov x16, x0")
            for i in range(len(expr.args) - 1):
                lines.append(f"  ldr x{i}, [sp], #16")
            lines.append("  svc #0x80")
        elif expr.kind == 'str':
            idx = len(self.strings)
            self.strings.append(expr.val)
            lines.append(f"  adrp x0, str_{idx}@PAGE")
            lines.append(f"  add x0, x0, str_{idx}@PAGEOFF")


# ─── Mach-O Writer ───────────────────────────────────────────────────────────

def write_macho_header(f, cpu_type, cpu_subtype, ncmds, sizeofcmds):
    """Write Mach-O 64-bit header."""
    flags = MH_NOUNDEFS | MH_PIE
    f.write(struct.pack('<IIIIIIII',
        MH_MAGIC_64, cpu_type, cpu_subtype, MH_EXECUTE,
        ncmds, sizeofcmds, flags, 0))  # reserved=0

def write_segment_cmd(f, segname, vmaddr, vmsize, fileoff, filesize,
                      maxprot, initprot, nsects):
    """Write LC_SEGMENT_64."""
    name = segname.encode('utf-8').ljust(16, b'\0')
    f.write(struct.pack('<II', LC_SEGMENT_64, 72 + nsects * 80))
    f.write(name)
    f.write(struct.pack('<QQQQIIII',
        vmaddr, vmsize, fileoff, filesize, maxprot, initprot, nsects, 0))

def write_section(f, sectname, segname, addr, size, offset, align,
                  reloff, nreloc, flags):
    """Write section header (within segment)."""
    sn = sectname.encode('utf-8').ljust(16, b'\0')
    sg = segname.encode('utf-8').ljust(16, b'\0')
    f.write(sn + sg)
    f.write(struct.pack('<QQIIIIIII', addr, size, offset, align, reloff, nreloc,
                        flags, 0, 0))

def write_main_cmd(f, entryoff, stacksize=0):
    """Write LC_MAIN."""
    f.write(struct.pack('<IIQI', LC_MAIN, 24, entryoff, stacksize))

def write_build_version_cmd(f, platform=PLATFORM_MACOS, minos=0x000D0000,
                            sdk=0x000E0000):
    """Write LC_BUILD_VERSION."""
    f.write(struct.pack('<IIIIII', LC_BUILD_VERSION, 24, platform, minos, sdk, 0))

def write_fat_header(f, slices):
    """Write fat/universal binary header."""
    f.write(struct.pack('>II', 0xCAFEBABE, len(slices)))
    for cpu_type, cpu_subtype, offset, size, align in slices:
        f.write(struct.pack('>IIIII', cpu_type, cpu_subtype, offset, size, align))


# ─── Assembly & Linking ──────────────────────────────────────────────────────

def assemble_macos(asm_source, output_path, arch):
    """Assemble and link on macOS using system tools."""
    with tempfile.TemporaryDirectory() as tmp:
        asm_path = os.path.join(tmp, "prog.s")
        obj_path = os.path.join(tmp, "prog.o")

        with open(asm_path, 'w') as f:
            f.write(asm_source)

        # Use system as + ld
        try:
            # Assemble
            subprocess.run(
                ['as', '-arch', arch, '-o', obj_path, asm_path],
                check=True, capture_output=True, text=True
            )
            # Link
            subprocess.run(
                ['ld', '-arch', arch, '-o', output_path, obj_path,
                 '-lSystem', '-syslibroot',
                 '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk',
                 '-e', '_main'],
                check=True, capture_output=True, text=True
            )
            return True
        except subprocess.CalledProcessError as e:
            print(f"Assembly/link error: {e.stderr}", file=sys.stderr)
            return False
        except FileNotFoundError:
            print("error: system assembler (as) not found. Install Xcode Command Line Tools.", file=sys.stderr)
            return False


def build_universal(x86_path, arm64_path, output_path):
    """Create universal binary using lipo."""
    try:
        subprocess.run(
            ['lipo', '-create', '-output', output_path, x86_path, arm64_path],
            check=True, capture_output=True, text=True
        )
        return True
    except subprocess.CalledProcessError as e:
        print(f"lipo error: {e.stderr}", file=sys.stderr)
        return False


def ad_hoc_sign(binary_path):
    """Ad-hoc code sign (required for ARM64 macOS)."""
    try:
        subprocess.run(
            ['codesign', '-s', '-', '--force', binary_path],
            check=True, capture_output=True, text=True
        )
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


# ─── Main ────────────────────────────────────────────────────────────────────

def detect_arch():
    """Detect native architecture."""
    machine = platform.machine().lower()
    if machine in ('arm64', 'aarch64'):
        return 'arm64'
    return 'x86_64'

def main():
    args = sys.argv[1:]

    if not args:
        print("jda-macos — macOS native compiler for Jda")
        print()
        print("Usage:")
        print("  jda-macos.sh <file.jda>                    Compile to native macOS binary")
        print("  jda-macos.sh --arch arm64 <file.jda>       Compile for ARM64")
        print("  jda-macos.sh --arch x86_64 <file.jda>      Compile for x86-64")
        print("  jda-macos.sh --universal <file.jda>         Universal binary (both archs)")
        print("  jda-macos.sh --asm <file.jda>              Output assembly only")
        print("  jda-macos.sh -o <output> <file.jda>        Specify output name")
        sys.exit(1)

    arch = detect_arch()
    asm_only = False
    universal = False
    output = None
    source = None

    i = 0
    while i < len(args):
        if args[i] == '--arch' and i + 1 < len(args):
            arch = args[i + 1]; i += 2
        elif args[i] == '--asm':
            asm_only = True; i += 1
        elif args[i] == '--universal':
            universal = True; i += 1
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

    if not output:
        output = os.path.splitext(os.path.basename(source))[0]

    if asm_only:
        if universal or arch == 'x86_64':
            gen = X86_64MacOSGen()
            print(f"; x86-64 macOS assembly")
            print(gen.generate(functions))
        if universal or arch == 'arm64':
            gen = ARM64MacOSGen2()
            if universal:
                print(f"\n; ARM64 macOS assembly")
            print(gen.generate(functions))
        sys.exit(0)

    if universal:
        # Build both architectures, then lipo
        with tempfile.TemporaryDirectory() as tmp:
            x86_path = os.path.join(tmp, f"{output}_x86_64")
            arm_path = os.path.join(tmp, f"{output}_arm64")

            gen_x86 = X86_64MacOSGen()
            asm_x86 = gen_x86.generate(functions)
            if not assemble_macos(asm_x86, x86_path, 'x86_64'):
                print("error: x86-64 build failed", file=sys.stderr)
                sys.exit(1)

            gen_arm = ARM64MacOSGen2()
            asm_arm = gen_arm.generate(functions)
            if not assemble_macos(asm_arm, arm_path, 'arm64'):
                print("error: ARM64 build failed", file=sys.stderr)
                sys.exit(1)

            if not build_universal(x86_path, arm_path, output):
                print("error: universal binary creation failed", file=sys.stderr)
                sys.exit(1)

            ad_hoc_sign(output)
            print(f"Universal binary: {output}")
            subprocess.run(['file', output])
    else:
        if arch == 'x86_64':
            gen = X86_64MacOSGen()
        else:
            gen = ARM64MacOSGen2()

        asm = gen.generate(functions)

        if not assemble_macos(asm, output, arch):
            sys.exit(1)

        ad_hoc_sign(output)
        print(f"Built: {output} ({arch})")
        subprocess.run(['file', output])

if __name__ == "__main__":
    main()
