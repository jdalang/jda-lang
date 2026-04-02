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
- [ ] Region-based allocation (arenas) for hot paths
- [ ] Linear types for resource safety (files, sockets must be consumed)

**Deliverable**: Ability to build CLI tools and servers in Jda.

---

## Phase 4 — Performance & Optimization

*Goal: Prove Jda can match C/Rust performance.*

- [ ] Graph-coloring register allocator
- [ ] Function inlining
- [ ] Tail-call optimization
- [ ] Loop tiling and cache-line optimization
- [ ] AVX-512 / NEON SIMD auto-vectorization pass in JIR
- [ ] Benchmark suite (vs C, Go, Rust)

---

## Phase 5 — Concurrency Runtime

*Goal: Match Go's concurrency with deterministic performance (no GC).*

- [ ] J-Threads — lightweight green threads with M:N work-stealing scheduler
- [ ] Actor model — isolated memory per actor, no shared state, no data races
- [ ] Lock-free channels with zero-copy message passing (ownership transfer)
- [ ] `spawn` keyword
- [ ] Deadlock detection

---

## Phase 6 — Native Machine Learning

*Goal: Replace Python as the ML language by making tensors and autograd native primitives.*

- [ ] First-class `Tensor` type with compile-time shape checking
- [ ] Compile-time autograd — compiler generates backward passes, no runtime graph
- [ ] Jda-to-PTX backend — direct GPU compilation without CUDA C++ runtime
- [ ] ROCm backend for AMD GPUs
- [ ] CPU AVX-512 vectorization pass for tensor operations
- [ ] Native ML standard library: `nn.Linear`, `nn.ReLU`, `optim.Adam` — all in Jda
- [ ] Transformer demo — train a model in pure Jda

---

## Phase 7 — Ecosystem & Tooling

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
