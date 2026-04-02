# Jda Compiler Architecture

## Bootstrap Pipeline

Jda is bootstrapped from assembly with zero external dependencies:

```
nasm + ld → jda0 (seed compiler, ~147K lines of x86-64 assembly)
     jda0 → jda1 (stage 1, compiles jda1.jda → 374 KB ELF binary)
     jda1 → jda1_sh2 (stage 2, self-compiled → 1.77 MB)
  jda1_sh2 → jda1_sh3 (stage 3 → 1.77 MB)
  jda1_sh3 → jda1_sh4 (stage 4 → 1.77 MB, identical to stage 3)
```

Stage 3 and stage 4 are byte-identical, proving the compiler is a fixed point.

## Compiler Stages

### jda0 — Seed Compiler

Hand-written NASM x86-64 assembly (`bootstrap/stage0/jda0.asm`). Single-pass compiler that reads `.jda` source and emits ELF binaries directly. No intermediate representation.

Key constraints:
- One-pass: no forward references for functions (resolved via fixup patching)
- Uses `r15` as global base pointer
- `print()` built-in uses `rsi` — clobbers argv after any print call

### jda1 — The Real Compiler

Written in Jda (`bootstrap/stage1/jda1.jda`, ~330K characters). Multi-pass architecture:

1. **Lexer** — tokenizes source into `Token` structs (67K+ tokens for self-compilation)
2. **Parser / Codegen** — Pratt parser that directly emits JIR (Jda Intermediate Representation)
3. **Optimization** — constant folding and dead code elimination (DCE)
4. **Register Allocator** — pool-based with spill to stack
5. **Lowering** — JIR → x86-64 machine code
6. **ELF Writer** — emits PT_LOAD ELF binary with .text and .rodata

### JIR (Jda Intermediate Representation)

SSA-style instructions organized in basic blocks:

- `OP_CONST`, `OP_ADD`, `OP_SUB`, `OP_MUL` — arithmetic
- `OP_CMP_EQ`, `OP_CMP_LT`, `OP_CMP_GT` — comparisons
- `OP_LOAD`, `OP_STORE` — stack slot access
- `OP_LOAD_MEM`, `OP_STORE_MEM` — memory access
- `OP_BR`, `OP_JMP` — control flow
- `OP_CALL`, `OP_SYSCALL` — function/system calls
- `OP_STRLIT`, `OP_STRLEN` — string handling
- `OP_ALLOC` — stack allocation for structs/arrays

### Key Data Structures

| Struct | Size | Purpose |
|--------|------|---------|
| `Token` | 32 B | Lexer output (type, string span, immediate) |
| `Instr` | 96 B | JIR instruction (op, operands, type, metadata) |
| `BasicBlock` | 196 KB | Block of up to 128 instructions |
| `JirFunction` | 6.3 MB | Up to 256 basic blocks + variable bindings + strtab |
| `LowerCtx` | 100 KB | Register allocator state + fixup table |
| `StructTable` | 199 KB | Struct definitions with field offsets |

`JirFunction` and `LowerCtx` are allocated once and reused across all functions to avoid stack overflow.

## Known Workarounds

These patterns exist because jda0 has specific miscompilation bugs:

1. **No unconditional `loop {}`** — jda0 miscompiles the missing condition, causing the loop body to be skipped. Use `loop var == 1 { ... }` instead.

2. **No direct `out[idx] = val` byte stores in lowering code** — miscompiled in self-hosted output. Use `poke_byte(out, idx, val)` wrapper.

3. **No `rex_byte()` function calls** — 4-argument function calls are miscompiled by jda0. The REX byte computation is inlined at all 18 call sites.

These workarounds can be removed once jda0 is retired and jda1 becomes the bootstrap compiler.

## Build System

The `Makefile` in `bootstrap/stage0/` handles assembly and linking:

```bash
make stage1    # nasm jda0.asm → jda0.o → jda0 → jda1
```

Self-host stages run in Docker (Linux x86-64 on any host):

```bash
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v $(PWD)/bootstrap:/jda -w /jda/stage0 jda-build sh -c \
  "./jda1 ../stage1/jda1.jda jda1_sh2"
```

The large stack ulimit (500 MB) is needed because `JirFunction` is 6.3 MB and the compiler processes 250+ functions.
