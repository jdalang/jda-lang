# Jda Compiler Architecture

Jda bypasses LLVM and builds its own compiler pipeline entirely in Jda — from lexer to machine code. No C, no C++, no external compiler infrastructure.

## Bootstrap Pipeline

The default build uses the self-hosted bootstrap compiler — no NASM or assembly tools required:

```
jda1-bootstrap → jda1 (compiles jda1.jda → 1.77 MB ELF binary)
         jda1 → jda1_b (self-compiled → 1.77 MB, identical to jda1)
```

The bootstrap binary (`bootstrap/bin/jda1-bootstrap`) is itself a converged self-hosted compiler. It is checked into git with a SHA-256 checksum.

### Historical Bootstrap (jda0, retired)

The original bootstrap path used hand-written assembly:

```
nasm + ld → jda0 (seed compiler, ~147K lines of x86-64 assembly)
     jda0 → jda1 (stage 1, 374 KB)
     jda1 → jda1_sh2 (stage 2, 1.77 MB)
  jda1_sh2 → jda1_sh3 (stage 3, 1.77 MB)
  jda1_sh3 → jda1_sh4 (stage 4, 1.77 MB, identical to stage 3)
```

jda0 source is preserved in `bootstrap/stage0/` for historical reference. The legacy build can be invoked with `make stage1-from-asm` (requires NASM).

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

These workarounds exist because the code must still compile correctly when built by jda0 (legacy path). Once jda0 is fully retired and the self-hosted bootstrap is the only build path, these can be cleaned up — though they are harmless and the self-hosted compiler handles them correctly.

## Build System

The `Makefile` in `bootstrap/stage0/` builds jda1 from the self-hosted bootstrap compiler:

```bash
make stage1      # jda1-bootstrap compiles jda1.jda → jda1
make selfhost    # full 4-stage convergence verification
make test        # compile and run hello.jda
```

Legacy build from assembly (requires NASM):

```bash
make stage1-from-asm   # nasm → jda0 → jda1
```

All builds run in Docker (Linux x86-64 on any host):

```bash
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v $(PWD):/jda -w /jda/bootstrap/stage0 jda-build make stage1
```

The large stack ulimit (500 MB) is needed because `JirFunction` is 6.3 MB and the compiler processes 250+ functions.

### Updating the Bootstrap Binary

When `jda1.jda` changes, the bootstrap binary must be updated:

```bash
make update-bootstrap   # selfhost → verify convergence → copy to bootstrap/bin/
```

Then commit `bootstrap/bin/jda1-bootstrap` and `bootstrap/bin/CHECKSUMS`.

## Future Architecture

JIR is designed to grow beyond basic x86-64 code generation:

- **Optimization passes** — loop tiling, SIMD auto-vectorization (AVX-512/NEON), all written in Jda
- **GPU backends** — JIR → PTX (NVIDIA) and ROCm (AMD) for native tensor compilation
- **ARM64 backend** — direct machine code generation for Apple Silicon and ARM servers
- **Compile-time autograd** — JIR analysis to generate backward passes for ML training

The goal is a fully self-contained compiler infrastructure where every optimization pass and backend is written in Jda itself — no LLVM, no MLIR, no C++ anywhere in the stack.
