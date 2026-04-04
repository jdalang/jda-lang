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

## Phase 7 — Native Machine Learning

*Goal: Replace Python as the ML language by making tensors and autograd native primitives.*

- [x] M1: Floating point types — f64 builtins (13 ops: arithmetic, cmp, sqrt, neg, print) ✅
- [ ] M2: Float printing & math builtins (exp, log, pow, sin, cos, tanh)
- [ ] M3: Heap-allocated Tensor type with shape metadata
- [ ] M4: CPU tensor operations (matmul, elementwise, reductions)
- [ ] M5: AVX-512 vectorization
- [ ] M6: Compile-time autograd — compiler generates backward passes, no runtime graph
- [ ] M7: Neural network library (Linear, ReLU, SGD, Adam)
- [ ] M8: Jda-to-PTX backend — direct GPU compilation without CUDA C++ runtime
- [ ] M9: ROCm backend for AMD GPUs
- [ ] M10: Transformer demo — train a model in pure Jda

---

## Phase 8 — Ecosystem & Tooling

- [ ] Package manager
- [ ] Language server (LSP)
- [ ] Formatter
- [ ] Test framework
- [ ] Documentation site
- [ ] WASM playground
- [ ] macOS and Windows backends
- [ ] ARM64 backend

---

## Timeline (Solo Developer)

| Milestone | Target |
|-----------|--------|
| Self-hosting | ✅ April 2026 |
| Usable 0.1 release | ~2 months |
| Strong language core | ~8 months |
| Performance credibility | ~12 months |
| Concurrency or ML identity | ~18 months |
| Ecosystem maturity | ~24 months |
