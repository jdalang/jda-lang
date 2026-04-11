# Jda Compiler Architecture

The Jda compiler (`bootstrap/stage1/jda1.jda`) is a self-hosted compiler written entirely in Jda. It compiles `.jda` source files to native x86-64 Linux ELF binaries with no external dependencies.

## Pipeline

```
Source (.jda)
    │
    ▼
  Lexer/Tokenizer
    │  Converts source to token stream
    ▼
  Parser
    │  Builds AST from tokens
    ▼
  JIR (Jda Intermediate Representation)
    │  SSA-based IR with basic blocks
    ▼
  Optimization
    │  Constant folding, dead code elimination
    ▼
  Register Allocation
    │  Linear scan with spill support
    ▼
  x86-64 Code Generation
    │  Direct machine code emission
    ▼
  ELF Binary Output
    │  Statically linked, no libc
    ▼
  Native executable
```

## Key Data Structures

| Struct | Size | Purpose |
|--------|------|---------|
| `Token` | 40B | Lexer token (type, offset, length, immediate value) |
| `Node` | — | AST node |
| `Instr` | 96B | SSA instruction in a basic block |
| `BasicBlock` | 196KB | Block of up to 128 instructions |
| `JirFunction` | 6.3MB | Full function IR (256 basic blocks) |
| `LowerCtx` | 100KB | Code generation context |
| `StructTable` | 199KB | Struct metadata (fields, sizes, offsets) |
| `RegAlloc` | — | Register allocation state |
| `Fixup` | — | Cross-reference fixup for linking |

## Compilation Phases

### 1. Tokenization
Scans source into tokens: identifiers, keywords, integers, strings, operators, etc.

### 2. Parsing & AST
Recursive descent parser builds an AST. Handles:
- Function declarations with type annotations
- Struct definitions with field types and arrays
- Const declarations
- Trait and impl blocks
- Generic function scanning (`<T>`, `<const N>`)
- Derive attribute processing

### 3. Generic Expansion
- `scan_generic_fns()` — finds `fn name<T>()` and `fn name<const N>()` patterns
- `expand_all_generics()` — monomorphizes: `add<i64>` → `add_i64`, `double<21>` → `double_21`
- `copy_generic_toks()` — duplicates function tokens with type/const substitution

### 4. JIR Generation
Converts AST to SSA-based intermediate representation:
- Each function gets a `JirFunction` with up to 256 basic blocks
- Instructions in SSA form (each value defined exactly once)
- Handles: arithmetic, comparisons, loads, stores, calls, branches, phi nodes

### 5. Optimization
- **Constant folding**: Evaluate constant expressions at compile time
- **Dead code elimination**: Remove unused instructions
- Applied per-function on the JIR

### 6. Register Allocation
Linear scan allocator over live ranges:
- 14 general-purpose registers (excludes rsp, rbp)
- Spill to stack when registers exhausted
- Calling convention: rdi, rsi, rdx, rcx for first 4 args

### 7. x86-64 Lowering
Direct machine code emission:
- One-pass lowering from JIR to x86-64 bytes
- Handles: MOV, ADD, SUB, IMUL, IDIV, CMP, Jcc, CALL, RET, PUSH, POP
- Syscall emission via `syscall` instruction
- Inline assembly passthrough

### 8. ELF Output
Writes a complete ELF64 executable:
- ELF header + program header
- `.text` section (code)
- `.data` section (string literals, globals)
- Entry point jumps to `main()`
- No dynamic linking, no libc

## Self-Hosting

The compiler compiles itself:

```
jda0 (assembly) → jda1.jda → jda1 (binary)
jda1 → jda1.jda → jda1_sh2 (self-hosted)
jda1_sh2 → jda1.jda → jda1_sh3 (converged)
```

Convergence is verified by `jda1_sh2 == jda1_sh3` (byte-identical).

## Source Layout

The compiler source `bootstrap/stage1/jda1.jda` is a single file organized as:

| Section | Lines (approx) | Contents |
|---------|----------------|----------|
| Constants & Globals | 1-500 | Token types, opcodes, global tables |
| Struct Definitions | 260-400 | Token, Node, Instr, BasicBlock, etc. |
| String Utilities | 500-800 | str_match, str_to_int, etc. |
| Tokenizer | 800-1500 | scan_token, tokenize |
| Generic Expansion | 1100-1600 | scan_generic_fns, expand_all_generics |
| Parser | 1600-3000 | parse_expr, parse_stmt, parse_fn |
| Trait/Impl | 3000-3500 | parse_trait, parse_impl, derive |
| JIR Generation | 3500-8000 | compile_expr, compile_stmt, inline codegen |
| Optimization | 8000-8500 | constant_fold, dead_code_elim |
| Register Allocator | 8500-9500 | linear_scan, spill |
| x86-64 Lowering | 9500-18000 | lower_instr, emit_* functions |
| ELF Writer | 18000-19500 | write_elf_header, write_sections |
| Linker/Fixup | 19500-20800 | resolve_calls, fixup_branches |
| Main/Live Codegen | 20800-end | main(), live_codegen for main() |

## Conformance Tests

291 pass tests + 7 fail tests in `tests/conformance/stage1/`:

```
tests/conformance/stage1/pass/    # Programs that should compile and run
tests/conformance/stage1/fail/    # Programs that should fail to compile
```

Each pass test has a `.jda` source and `.expected` output file.
