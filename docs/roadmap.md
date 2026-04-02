# Jda Roadmap

## Stage 1 — Self-Hosting Lock ✅ COMPLETE (April 2, 2026)

The compiler compiles itself and reaches a fixed point.

**Delivered:**
- Multi-function programs (250+ functions)
- Struct definitions with field access and nested fields
- Array declarations and indexing (stack and mmap-backed)
- Pointer/reference support (address-of, dereference, pass-by-reference)
- const declarations with global constant tables
- Logical operators (and, or), comparison operators (==, !=, <, >, <=, >=)
- else-if chains
- String escape sequences (\n, \t, \\, \")
- print(string), print_i64(int)
- 6-argument function calls (System V ABI)
- Inline asm blocks
- syscall() built-in
- SSA-based JIR with constant folding and DCE
- Register allocator with spill support
- x86-64 lowering and ELF64 binary output
- Convergence: jda1_sh3 == jda1_sh4

## Stage 2 — Minimal Release (Next)

Make Jda usable for external developers.

**Goals:**
- CLI interface (`jda build`, `jda run`)
- Proper error diagnostics with line/column reporting
- Linux installer script
- Minimal standard library (fs, time, fmt)
- Remove jda0 dependency — use self-hosted jda1 as the bootstrap compiler
- Versioning

**Deliverable:** One-command install and build workflow.

## Stage 3 — Language Core Maturity

Implement the features needed for real-world programs.

**Goals:**
- Full type checking and type inference
- Enums and pattern matching
- Result<T, E> and `?` operator
- impl blocks and methods
- Minimal generics (monomorphization)
- Basic ownership model (single-owner rule)

**Deliverable:** Ability to build CLI tools and servers in Jda.

## Stage 4 — Performance

**Goals:**
- Graph-coloring register allocator
- Function inlining
- Tail-call optimization
- Loop unrolling
- Benchmark suite (vs C, Go, Rust)

## Stage 5 — Concurrency (Optional Path A)

- Lightweight threads (J-Threads)
- Lock-free channels
- Work-stealing scheduler
- `spawn` keyword
- Deadlock detection

## Stage 6 — ML Runtime (Optional Path B)

- Tensor primitives with compile-time shape checking
- Autograd
- SIMD vectorization
- GPU backend (PTX/ROCm)
- Transformer demo

## Stage 7 — Ecosystem

- Package manager
- Language server (LSP)
- Formatter
- Test framework
- Documentation site
- WASM playground
- macOS and Windows backends
