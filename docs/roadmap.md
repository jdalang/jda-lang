# Jda Roadmap

## Phase 1 — Bootstrapping & Self-Hosting ✅ COMPLETE

*Goal: Get a working compiler without touching C, C++, or any existing high-level language.*

**Delivered (April 2, 2026):**
- Stage 0 compiler in raw x86-64 assembly (NASM) — direct Linux syscalls, no libc
- Stage 1 compiler written in Jda — lexer, parser, JIR codegen, optimizer, register allocator, x86-64 lowering, ELF writer
- Full self-hosting: jda1 compiles itself to an identical binary (convergence proven)
- SSA-based JIR with constant folding and dead code elimination
- Multi-function programs (250+ functions), structs, arrays, pointers, inline asm, syscalls

**C and C++ are officially eliminated from the toolchain.**

---

## Phase 2 — Minimal Release ✅ COMPLETE

*Goal: Make Jda usable by external developers.*

- [x] CLI interface (`jda build`, `jda run`) ✅
- [x] Line/column tracking in lexer ✅
- [x] Error diagnostics with source context ✅
- [x] Linux installer script ✅
- [x] Retire jda0 — use self-hosted jda1 as the bootstrap compiler ✅
- [x] Minimal standard library: `fs` (file I/O via syscalls), `fmt` (formatting), `time` ✅
- [x] Test runner & CI (50 conformance tests, GitHub Actions) ✅
- [x] Versioning and release process ✅

**Deliverable**: One-command install and build workflow.

**Cutting a release:**
```bash
# Update VERSION file, then:
git tag v0.1.0 && git push --tags
```
GitHub Actions will automatically build, verify convergence, and publish the release.

---

## Phase 3 — Language Core Maturity

*Goal: Make Jda powerful enough for real-world programs.*

- [x] Argument count checking at call sites ✅
- [x] Type inference from function return types ✅
- [x] Enums and pattern matching ✅
- [x] `Result<T, E>` and `?` operator ✅
- [x] `impl` blocks and methods ✅
- [x] Generics (monomorphization) ✅
- [x] Compile-Time Reference Counting (CTRC) — automated memory safety, no GC ✅
- [x] Region-based allocation (arenas) for hot paths ✅
- [x] Linear types for resource safety (files, sockets must be consumed) ✅

**Deliverable**: Ability to build CLI tools and servers in Jda.

**Phase 3 COMPLETE** (2026-04-02) — Capstone program compiles and outputs `300`. Self-host converged.

---

## Phase 4 — Performance & Optimization

*Goal: Prove Jda can match C/Rust performance.*

- [x] Constant folding + dead code elimination ✅
- [x] Expanded register allocator (7→10 regs, round-robin eviction) ✅
- [x] Function inlining (emit_byte, poke_byte x86-level) ✅
- [x] Tail-call optimization ✅
- [x] Peephole optimization ✅
- [x] Benchmark suite (vs C, fib35/sieve/sum_loop + self-compile) ✅

---

## Phase 5 — Performance Deep Dive

*Goal: Close the gap with C -O2. Target: fib35 <5x, sum_loop <3x, self-compile <5s.*

- [x] P1: Right-sized stack frames (524KB→actual usage, fib35: 709x→5.6x) ✅
- [x] P2: Conditional spilling (skip spill for single-use values, -264KB binary, fib35: 5.4x→5.0x) ✅
- [x] P3: Selective register save/restore (only save live regs around calls, -60KB binary) ✅
- [x] P4: Stack probe skip for small frames (<64KB, eliminates probe for all P1-sized frames) ✅
- [x] P5: Callee-saved register preference (push/pop R13-R15 in prologue/epilogue, fib35: 5.0x→3.7x) ✅

---

## Phase 6 — Concurrency Runtime ✅ COMPLETE

*Goal: Match Go's concurrency with deterministic performance (no GC).*

**Delivered (April 3, 2026):**
- [x] J-Threads — cooperative green threads with context switch, spawn keyword, 64KB stacks ✅
- [x] Lock-free channels — chan_new, chan_send, chan_recv, chan_close ✅
- [x] Atomic operations — atomic_load, atomic_store, atomic_cmpxchg, atomic_fetch_add ✅
- [x] Inline assembly blocks — `asm volatile {}` for context switch ✅
- [x] OS threading — clone_thread, futex_wait, futex_wake, get_tid, get_nprocs ✅
- [x] I/O multiplexing — epoll_create1, epoll_ctl, epoll_wait ✅
- [x] Deadlock detection — deadlock_check builtin ✅
- [x] 114 conformance tests, self-host converged at 1,787,169 bytes ✅

---

## Phase 7 — Native Machine Learning ✅ COMPLETE

*Goal: Replace Python as the ML language by making tensors and autograd native primitives.*

**Delivered (April 3, 2026):**
- [x] M1: Floating point types — f64 builtins (13 ops: arithmetic, cmp, sqrt, neg, print) ✅
- [x] M2: Math builtins — 7 transcendental functions (abs, exp, log, pow, sin, cos, tanh) via x87 FPU ✅
- [x] M3: Heap-allocated Tensor type — tensor_new, get, set, fill, free, shape, len ✅
- [x] M4: CPU tensor operations — matmul, elementwise add/sub/mul, reductions, activations ✅
- [x] M5: AVX-512 vectorization — EVEX-encoded SIMD ops for tensor kernels ✅
- [x] M6: Compile-time autograd — gradient rules for all ops, numerical verification ✅
- [x] M7: Neural network library — Linear, ReLU, SGD, MSE loss, XOR training demo ✅
- [x] M8: PTX backend — branchless NVIDIA GPU detection, CPU fallback matmul/vecadd ✅
- [x] M9: ROCm backend — AMD GPU detection via /dev/kfd, reuses GPU CPU fallback ✅
- [x] M10: Transformer demo — attention, layer norm, full forward pass with softmax ✅

150 conformance tests, self-host converged at 1,964,161 bytes.

---

## Phase 8 — Ecosystem & Tooling

### M1: Built-in Test Framework
- `jda test` command — discovers and runs test functions (`fn test_*`)
- Assertion builtins: `assert_eq`, `assert_ne`, `assert_true`, `assert_close` (for floats)
- Test output: pass/fail counts, failure messages with source location
- Replace the current conformance test runner (shell script + .expected files)

### M2: Package Manager
- `jda.toml` manifest file — name, version, dependencies, build config
- `jda pkg init` / `jda pkg add <name>` / `jda pkg build`
- Git-based dependency resolution (tag-pinned versions, no central registry initially)
- Module system: `import "pkg/module"` resolves from `jda.toml` deps
- Lockfile (`jda.lock`) for reproducible builds

### M3: Language Server Protocol (LSP)
- Written in Jda (self-hosted tooling)
- Go-to-definition, hover for type info, find references
- Diagnostics (compile errors as you type)
- JSON-RPC over stdio for editor integration
- VS Code extension as first target

### M4: Formatter
- `jda fmt` — canonical formatting for all Jda source files
- Consistent indentation (2 spaces), brace style, line length
- Idempotent: running twice produces same output
- `jda fmt --check` for CI enforcement

### M5: Documentation Generator
- `jda doc` — extract doc comments (`;; comment`) and generate HTML
- Per-function, per-struct, per-module documentation
- Cross-referenced with source links
- Static site output (deployable to GitHub Pages)

### M6: ARM64 Backend (aarch64-linux)
- New lowering pass: JIR → AArch64 instructions
- ABI: AAPCS64 (x0-x7 args, x19-x28 callee-saved, d0-d7 float args)
- NEON SIMD for tensor operations (128-bit vectors, 4x f32 or 2x f64)
- ELF writer for aarch64 (different relocations, section alignment)
- Target: Raspberry Pi 5, AWS Graviton, Apple Silicon (Linux VMs)
- Self-host on ARM64

### M7: macOS Backend (x86-64 and ARM64)
- Mach-O binary format writer (LC_SEGMENT_64, LC_SYMTAB, LC_MAIN)
- macOS syscall ABI (syscall numbers differ, `0x2000000` prefix)
- Code signing (ad-hoc, required for ARM64 macOS)
- Universal binary support (fat Mach-O: x86-64 + arm64)
- Target: native macOS development without Docker

### M8: WebAssembly Backend
- JIR → WASM bytecode lowering
- WASI target for CLI programs (file I/O, args, environment)
- Browser target for `jda playground` (interactive web REPL)
- Linear memory model mapping for tensors
- Hosted playground site with examples

### M9: Standard Library Expansion
- `net` — TCP/UDP client and server (already have epoll from Phase 6)
- `http` — HTTP/1.1 server and client (built on `net`)
- `crypto` — SHA-256, AES-256, HMAC (expand existing crypto.jda)
- `json` — JSON parser and serializer (expand existing json.jda)
- `io` — buffered reader/writer, stdin/stdout helpers
- `os` — environment variables, process spawning, signal handling
- `math` — integer math, random number generation, constants

### M10: CI/CD & Release Pipeline
- GitHub Actions: build + test on x86-64 Linux, ARM64 Linux, macOS
- Self-host convergence check in CI for every PR
- Benchmark regression detection (flag >5% slowdowns)
- Automated release builds: `.tar.gz` per platform, checksum file
- Install script: `curl -fsSL https://jda-lang.org/install.sh | sh`

---

## Timeline (Solo Developer)

| Milestone | Target |
|-----------|--------|
| Self-hosting | ✅ April 2026 |
| Usable 0.1 release | ✅ April 2026 |
| Strong language core | ✅ April 2026 |
| Performance credibility | ✅ April 2026 |
| Concurrency runtime | ✅ April 2026 |
| Native ML | ✅ April 2026 |
| Developer tooling (test, pkg, LSP, fmt) | Phase 8 M1-M5 |
| Cross-platform (ARM64, macOS, WASM) | Phase 8 M6-M8 |
| Production stdlib & CI | Phase 8 M9-M10 |
