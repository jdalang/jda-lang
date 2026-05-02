#!/usr/bin/env python3
"""
jda-arm64 — ARM64 (AArch64) cross-compiler for Jda

Compiles Jda source to aarch64-linux ELF binaries.
Implements: JIR-like lowering → AArch64 instructions → ELF writer.

ABI: AAPCS64
  - x0-x7: argument/result registers
  - x19-x28: callee-saved
  - x29: frame pointer (FP)
  - x30: link register (LR)
  - sp: stack pointer (16-byte aligned)
  - d0-d7: float args

Syscall convention (Linux aarch64):
  - x8: syscall number
  - x0-x5: arguments
  - svc #0

Usage:
  jda-arm64.sh <file.jda> <output>           Compile to ARM64 ELF
  jda-arm64.sh --asm <file.jda>              Output ARM64 assembly
  jda-arm64.sh --run <file.jda>              Compile and run via QEMU
"""

import sys
import os
import re
import struct
import tempfile
import subprocess

# ─── Lexer ────────────────────────────────────────────────────────────────────

class Token:
    def __init__(self, kind, value, line=0):
        self.kind = kind
        self.value = value
        self.line = line

def lex(source):
    tokens = []
    i = 0
    line = 1
    while i < len(source):
        c = source[i]
        if c == '\n':
            line += 1; i += 1
        elif c in ' \t\r':
            i += 1
        elif c == ';':
            while i < len(source) and source[i] != '\n': i += 1
        elif c == '"':
            j = i + 1
            while j < len(source) and source[j] != '"':
                if source[j] == '\\': j += 1
                j += 1
            tokens.append(Token('STR', source[i+1:j], line))
            i = j + 1
        elif c.isdigit():
            j = i
            while j < len(source) and source[j].isdigit(): j += 1
            tokens.append(Token('INT', int(source[i:j]), line))
            i = j
        elif c.isalpha() or c == '_':
            j = i
            while j < len(source) and (source[j].isalnum() or source[j] == '_'): j += 1
            word = source[i:j]
            tokens.append(Token('ID', word, line))
            i = j
        elif source[i:i+2] == '->':
            tokens.append(Token('->', '->', line)); i += 2
        elif source[i:i+2] == '!=':
            tokens.append(Token('!=', '!=', line)); i += 2
        elif source[i:i+2] == '==':
            tokens.append(Token('==', '==', line)); i += 2
        elif source[i:i+2] == '<=':
            tokens.append(Token('<=', '<=', line)); i += 2
        elif source[i:i+2] == '>=':
            tokens.append(Token('>=', '>=', line)); i += 2
        else:
            tokens.append(Token(c, c, line)); i += 1
    tokens.append(Token('EOF', '', line))
    return tokens

# ─── Parser ───────────────────────────────────────────────────────────────────

class Function:
    def __init__(self, name, params, ret_type, body):
        self.name = name
        self.params = params    # [(name, type)]
        self.ret_type = ret_type
        self.body = body        # list of statements

class Program:
    def __init__(self):
        self.functions = []
        self.strings = {}       # label -> string

def parse(tokens):
    prog = Program()
    pos = [0]

    def peek(): return tokens[pos[0]]
    def advance():
        t = tokens[pos[0]]; pos[0] += 1; return t
    def expect(kind):
        t = advance()
        if t.kind != kind: raise Exception(f"expected {kind}, got {t.kind} '{t.value}' at line {t.line}")
        return t

    def parse_fn():
        advance()  # fn
        name = expect('ID').value
        expect('(')
        params = []
        while peek().kind != ')':
            pname = expect('ID').value
            expect(':')
            ptype = expect('ID').value
            params.append((pname, ptype))
            if peek().kind == ',': advance()
        expect(')')
        ret_type = 'void'
        if peek().kind == '->':
            advance()
            ret_type = expect('ID').value
        expect('{')
        body = parse_block()
        expect('}')
        return Function(name, params, ret_type, body)

    def parse_block():
        stmts = []
        while peek().kind != '}' and peek().kind != 'EOF':
            stmts.append(parse_stmt())
        return stmts

    def parse_stmt():
        t = peek()
        if t.kind == 'ID':
            if t.value == 'let':
                return parse_let()
            elif t.value == 'if':
                return parse_if()
            elif t.value == 'ret':
                return parse_ret()
            elif t.value == 'print':
                return parse_print()
            elif t.value == 'syscall':
                return parse_syscall()
            else:
                return parse_expr_stmt()
        return ('skip', advance())

    def parse_let():
        advance()  # let
        name = expect('ID').value
        expect('=')
        expr = parse_expr()
        return ('let', name, expr)

    def parse_if():
        advance()  # if
        cond = parse_expr()
        expect('{')
        body = parse_block()
        expect('}')
        return ('if', cond, body)

    def parse_ret():
        advance()  # ret
        if peek().kind == '}':
            return ('ret', ('int', 0))
        return ('ret', parse_expr())

    def parse_print():
        advance()  # print
        has_paren = peek().kind == '('
        if has_paren:
            advance()
        s = expect('STR').value
        if has_paren:
            expect(')')
        label = f".str{len(prog.strings)}"
        prog.strings[label] = s
        return ('print', label, len(s))

    def parse_syscall():
        advance()  # syscall
        expect('(')
        args = [parse_expr()]
        while peek().kind == ',':
            advance()
            args.append(parse_expr())
        expect(')')
        return ('syscall', args)

    def parse_expr_stmt():
        expr = parse_expr()
        return ('expr', expr)

    def parse_expr():
        left = parse_unary()
        while peek().kind in ('+', '-', '*', '/', '==', '!=', '<', '>', '<=', '>='):
            op = advance().kind
            right = parse_unary()
            left = ('binop', op, left, right)
        return left

    def parse_unary():
        if peek().kind == '(':
            advance()
            e = parse_expr()
            expect(')')
            return e
        if peek().kind == 'INT':
            return ('int', advance().value)
        if peek().kind == 'ID':
            name = advance().value
            if peek().kind == '(':
                advance()
                args = []
                while peek().kind != ')':
                    args.append(parse_expr())
                    if peek().kind == ',': advance()
                expect(')')
                return ('call', name, args)
            return ('var', name)
        raise Exception(f"unexpected {peek().kind} '{peek().value}' at line {peek().line}")

    while peek().kind != 'EOF':
        if peek().kind == 'ID' and peek().value == 'fn':
            prog.functions.append(parse_fn())
        else:
            advance()
    return prog

# ─── ARM64 Code Generator ────────────────────────────────────────────────────

class ARM64Gen:
    def __init__(self, prog):
        self.prog = prog
        self.asm = []
        self.label_count = 0
        self.locals = {}
        self.stack_size = 0

    def new_label(self):
        self.label_count += 1
        return f".L{self.label_count}"

    def emit(self, line):
        self.asm.append(line)

    def generate(self):
        self.emit(".section .text")
        self.emit(".global _start")
        self.emit("")

        for fn in self.prog.functions:
            self.gen_function(fn)

        # _start calls main and exits
        self.emit("_start:")
        self.emit("  bl main")
        self.emit("  mov x8, #93")        # exit syscall
        self.emit("  svc #0")
        self.emit("")

        # String data
        if self.prog.strings:
            self.emit(".section .rodata")
            for label, s in self.prog.strings.items():
                escaped = s.encode('utf-8')
                self.emit(f"{label}:")
                hex_bytes = ','.join(f'0x{b:02x}' for b in escaped)
                self.emit(f"  .byte {hex_bytes}")
                # Add newline
                self.emit(f"{label}_nl:")
                self.emit(f"  .byte 0x0a")
            self.emit("")

        return '\n'.join(self.asm)

    def gen_function(self, fn):
        self.locals = {}
        # Allocate locals: parameters + local variables
        local_names = [p[0] for p in fn.params]
        for stmt in fn.body:
            if isinstance(stmt, tuple) and stmt[0] == 'let':
                local_names.append(stmt[1])

        # Stack frame: 16-byte aligned, save FP+LR + locals
        n_locals = len(local_names)
        frame_size = ((n_locals + 2) * 8 + 15) & ~15  # align to 16
        self.stack_size = frame_size

        for i, name in enumerate(local_names):
            self.locals[name] = (i + 2) * 8  # offset from SP (after FP+LR)

        self.emit(f"{fn.name}:")
        # Prologue
        self.emit(f"  stp x29, x30, [sp, #-{frame_size}]!")
        self.emit(f"  mov x29, sp")

        # Save parameters to stack
        for i, (pname, ptype) in enumerate(fn.params):
            if i < 8:
                off = self.locals[pname]
                self.emit(f"  str x{i}, [x29, #{off}]")

        # Generate body
        for stmt in fn.body:
            self.gen_stmt(stmt)

        # Epilogue (fallthrough)
        self.emit(f"  mov x0, #0")
        self.emit(f"  ldp x29, x30, [sp], #{frame_size}")
        self.emit(f"  ret")
        self.emit("")

    def gen_stmt(self, stmt):
        if stmt[0] == 'let':
            _, name, expr = stmt
            self.gen_expr(expr)  # result in x0
            off = self.locals[name]
            self.emit(f"  str x0, [x29, #{off}]")

        elif stmt[0] == 'ret':
            _, expr = stmt
            self.gen_expr(expr)
            self.emit(f"  ldp x29, x30, [sp], #{self.stack_size}")
            self.emit(f"  ret")

        elif stmt[0] == 'if':
            _, cond, body = stmt
            else_label = self.new_label()
            self.gen_expr(cond)
            self.emit(f"  cbz x0, {else_label}")
            for s in body:
                self.gen_stmt(s)
            self.emit(f"{else_label}:")

        elif stmt[0] == 'print':
            _, label, length = stmt
            self.emit(f"  mov x0, #1")          # fd = stdout
            self.emit(f"  adrp x1, {label}")
            self.emit(f"  add x1, x1, :lo12:{label}")
            self.emit(f"  mov x2, #{length}")
            self.emit(f"  mov x8, #64")          # write syscall
            self.emit(f"  svc #0")
            # Print newline
            self.emit(f"  mov x0, #1")
            self.emit(f"  adrp x1, {label}_nl")
            self.emit(f"  add x1, x1, :lo12:{label}_nl")
            self.emit(f"  mov x2, #1")
            self.emit(f"  mov x8, #64")
            self.emit(f"  svc #0")

        elif stmt[0] == 'syscall':
            _, args = stmt
            # Syscall number in x8, args in x0-x5
            if len(args) > 0:
                self.gen_expr(args[0])
                self.emit(f"  mov x8, x0")
            for i in range(1, min(len(args), 7)):
                self.gen_expr(args[i])
                if i - 1 != 0:
                    self.emit(f"  mov x{i-1}, x0")
            self.emit(f"  svc #0")

        elif stmt[0] == 'expr':
            self.gen_expr(stmt[1])

    def gen_expr(self, expr):
        if expr[0] == 'int':
            val = expr[1]
            if val < 0:
                self.emit(f"  mov x0, #{-val}")
                self.emit(f"  neg x0, x0")
            elif val <= 65535:
                self.emit(f"  mov x0, #{val}")
            else:
                # Load large immediate
                self.emit(f"  mov x0, #{val & 0xffff}")
                if val > 0xffff:
                    self.emit(f"  movk x0, #{(val >> 16) & 0xffff}, lsl #16")
                if val > 0xffffffff:
                    self.emit(f"  movk x0, #{(val >> 32) & 0xffff}, lsl #32")
                if val > 0xffffffffffff:
                    self.emit(f"  movk x0, #{(val >> 48) & 0xffff}, lsl #48")

        elif expr[0] == 'var':
            name = expr[1]
            off = self.locals.get(name, 0)
            self.emit(f"  ldr x0, [x29, #{off}]")

        elif expr[0] == 'binop':
            _, op, left, right = expr
            self.gen_expr(right)
            self.emit(f"  str x0, [sp, #-16]!")  # push right
            self.gen_expr(left)
            self.emit(f"  ldr x1, [sp], #16")    # pop right into x1

            if op == '+':
                self.emit(f"  add x0, x0, x1")
            elif op == '-':
                self.emit(f"  sub x0, x0, x1")
            elif op == '*':
                self.emit(f"  mul x0, x0, x1")
            elif op == '/':
                self.emit(f"  sdiv x0, x0, x1")
            elif op == '==':
                self.emit(f"  cmp x0, x1")
                self.emit(f"  cset x0, eq")
            elif op == '!=':
                self.emit(f"  cmp x0, x1")
                self.emit(f"  cset x0, ne")
            elif op == '<':
                self.emit(f"  cmp x0, x1")
                self.emit(f"  cset x0, lt")
            elif op == '>':
                self.emit(f"  cmp x0, x1")
                self.emit(f"  cset x0, gt")
            elif op == '<=':
                self.emit(f"  cmp x0, x1")
                self.emit(f"  cset x0, le")
            elif op == '>=':
                self.emit(f"  cmp x0, x1")
                self.emit(f"  cset x0, ge")

        elif expr[0] == 'call':
            _, name, args = expr
            # Save args to stack, then load into x0-x7
            for i, arg in enumerate(args):
                self.gen_expr(arg)
                if i < 8:
                    self.emit(f"  str x0, [sp, #-16]!")
            # Pop args into registers (reverse order)
            for i in range(len(args) - 1, -1, -1):
                if i < 8:
                    self.emit(f"  ldr x{i}, [sp], #16")
            self.emit(f"  bl {name}")

# ─── ELF Writer (aarch64) ────────────────────────────────────────────────────

def write_elf_aarch64(code_bytes, rodata_bytes, entry_offset, output_path):
    """Write a minimal static ELF binary for aarch64-linux."""
    # ELF constants
    ET_EXEC = 2
    EM_AARCH64 = 183
    EV_CURRENT = 1
    PT_LOAD = 1
    PF_R = 4
    PF_W = 2
    PF_X = 1

    EHDR_SIZE = 64
    PHDR_SIZE = 56

    # Two segments: text (RX) and rodata (R)
    n_phdr = 2 if rodata_bytes else 1
    headers_size = EHDR_SIZE + n_phdr * PHDR_SIZE

    # Align code to page
    code_offset = (headers_size + 0xfff) & ~0xfff
    code_vaddr = 0x400000 + code_offset
    code_size = len(code_bytes)

    rodata_offset = 0
    rodata_vaddr = 0
    rodata_size = len(rodata_bytes) if rodata_bytes else 0
    if rodata_size:
        rodata_offset = ((code_offset + code_size + 0xfff) & ~0xfff)
        rodata_vaddr = 0x400000 + rodata_offset

    entry = code_vaddr + entry_offset

    # Build ELF
    elf = bytearray()

    # ELF header
    elf += b'\x7fELF'               # magic
    elf += bytes([2])                # 64-bit
    elf += bytes([1])                # little-endian
    elf += bytes([EV_CURRENT])       # version
    elf += bytes([0])                # OS/ABI (NONE)
    elf += b'\x00' * 8              # padding
    elf += struct.pack('<H', ET_EXEC)
    elf += struct.pack('<H', EM_AARCH64)
    elf += struct.pack('<I', EV_CURRENT)
    elf += struct.pack('<Q', entry)
    elf += struct.pack('<Q', EHDR_SIZE)    # phoff
    elf += struct.pack('<Q', 0)            # shoff
    elf += struct.pack('<I', 0)            # flags
    elf += struct.pack('<H', EHDR_SIZE)
    elf += struct.pack('<H', PHDR_SIZE)
    elf += struct.pack('<H', n_phdr)
    elf += struct.pack('<H', 0)            # shentsize
    elf += struct.pack('<H', 0)            # shnum
    elf += struct.pack('<H', 0)            # shstrndx

    # Program headers
    # Text segment
    elf += struct.pack('<I', PT_LOAD)
    elf += struct.pack('<I', PF_R | PF_X)
    elf += struct.pack('<Q', code_offset)
    elf += struct.pack('<Q', code_vaddr)
    elf += struct.pack('<Q', code_vaddr)   # paddr
    elf += struct.pack('<Q', code_size)
    elf += struct.pack('<Q', code_size)
    elf += struct.pack('<Q', 0x1000)       # align

    if rodata_size:
        elf += struct.pack('<I', PT_LOAD)
        elf += struct.pack('<I', PF_R)
        elf += struct.pack('<Q', rodata_offset)
        elf += struct.pack('<Q', rodata_vaddr)
        elf += struct.pack('<Q', rodata_vaddr)
        elf += struct.pack('<Q', rodata_size)
        elf += struct.pack('<Q', rodata_size)
        elf += struct.pack('<Q', 0x1000)

    # Pad to code offset
    elf += b'\x00' * (code_offset - len(elf))
    elf += code_bytes

    # Pad to rodata offset
    if rodata_size:
        elf += b'\x00' * (rodata_offset - len(elf))
        elf += rodata_bytes

    with open(output_path, 'wb') as f:
        f.write(elf)
    os.chmod(output_path, 0o755)

# ─── Assembly via external tools ──────────────────────────────────────────────

def assemble_with_tools(asm_source, output_path):
    """Assemble ARM64 using aarch64-linux-gnu-as + ld (or Docker)."""
    with tempfile.TemporaryDirectory() as tmpdir:
        asm_path = os.path.join(tmpdir, "prog.s")
        obj_path = os.path.join(tmpdir, "prog.o")
        bin_path = os.path.join(tmpdir, "prog")

        with open(asm_path, "w") as f:
            f.write(asm_source)

        # Try native tools first, then Docker
        as_cmd = None
        ld_cmd = None

        for prefix in ["aarch64-linux-gnu-", "aarch64-linux-musl-", ""]:
            try:
                subprocess.run([f"{prefix}as", "--version"],
                             capture_output=True, check=True)
                as_cmd = f"{prefix}as"
                ld_cmd = f"{prefix}ld"
                break
            except (FileNotFoundError, subprocess.CalledProcessError):
                continue

        if as_cmd:
            subprocess.run([as_cmd, "-o", obj_path, asm_path], check=True,
                         capture_output=True)
            subprocess.run([ld_cmd, "-o", bin_path, obj_path, "-static"],
                         check=True, capture_output=True)
        else:
            # Use Docker with cross-compilation tools
            subprocess.run([
                "docker", "run", "--rm", "--platform", "linux/amd64",
                "-v", f"{tmpdir}:{tmpdir}", "-w", tmpdir,
                "jda-build", "sh", "-c",
                f"apt-get update -qq && apt-get install -qq -y binutils-aarch64-linux-gnu >/dev/null 2>&1 && "
                f"aarch64-linux-gnu-as -o {obj_path} {asm_path} && "
                f"aarch64-linux-gnu-ld -o {bin_path} {obj_path} -static"
            ], check=True, capture_output=True)

        # Copy result
        import shutil
        shutil.copy2(bin_path, output_path)

def run_with_qemu(binary_path):
    """Run ARM64 binary using qemu-aarch64."""
    try:
        result = subprocess.run(
            ["qemu-aarch64", binary_path],
            capture_output=True, text=True, timeout=10
        )
        sys.stdout.write(result.stdout)
        if result.stderr:
            sys.stderr.write(result.stderr)
        return result.returncode
    except FileNotFoundError:
        # Try Docker with QEMU
        abs_path = os.path.abspath(binary_path)
        result = subprocess.run([
            "docker", "run", "--rm", "--platform", "linux/arm64",
            "-v", f"{os.path.dirname(abs_path)}:/work", "-w", "/work",
            "arm64v8/ubuntu:22.04",
            f"./{os.path.basename(abs_path)}"
        ], capture_output=True, text=True, timeout=10)
        sys.stdout.write(result.stdout)
        return result.returncode

# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    args = sys.argv[1:]

    if not args:
        print("jda-arm64 — ARM64 cross-compiler for Jda")
        print()
        print("Usage:")
        print("  jda-arm64.sh <file.jda> <output>   Compile to ARM64 ELF")
        print("  jda-arm64.sh --asm <file.jda>       Output ARM64 assembly")
        print("  jda-arm64.sh --run <file.jda>       Compile and run via QEMU")
        print()
        print("Target: aarch64-linux (AAPCS64 ABI)")
        print("Requires: aarch64-linux-gnu-as/ld or Docker")
        sys.exit(1)

    asm_mode = False
    run_mode = False
    source_file = None
    output_file = None

    i = 0
    while i < len(args):
        if args[i] == "--asm":
            asm_mode = True
        elif args[i] == "--run":
            run_mode = True
        elif source_file is None:
            source_file = args[i]
        else:
            output_file = args[i]
        i += 1

    if not source_file:
        print("error: no source file specified", file=sys.stderr)
        sys.exit(1)

    with open(source_file) as f:
        source = f.read()

    # Lex and parse
    tokens = lex(source)
    prog = parse(tokens)

    # Generate ARM64 assembly
    gen = ARM64Gen(prog)
    asm = gen.generate()

    if asm_mode:
        print(asm)
        sys.exit(0)

    # Assemble to binary
    if not output_file:
        output_file = os.path.splitext(source_file)[0]

    try:
        assemble_with_tools(asm, output_file)
        print(f"  Compiled {source_file} -> {output_file} (aarch64-linux)")
    except Exception as e:
        print(f"error: assembly failed: {e}", file=sys.stderr)
        sys.exit(1)

    if run_mode:
        rc = run_with_qemu(output_file)
        sys.exit(rc)

if __name__ == "__main__":
    main()
