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

### M1: Built-in Test Framework ✅ COMPLETE

**Delivered (April 4, 2026):**
- [x] Assertion runtime functions: `assert_eq`, `assert_ne`, `assert_true`, `assert_close` — exit(1) on mismatch via syscall ✅
- [x] `jda test` command (`tools/jda-test.sh`) — discovers `fn test_*` functions, auto-generates main() wrapper, auto-prepends assertion runtime, reports pass/fail counts ✅
- [x] 4 new conformance tests using assertion functions ✅
- [x] 154 total conformance tests, self-host converged at 1,964,161 bytes ✅

### M2: Package Manager ✅ COMPLETE

**Delivered (April 4, 2026):**
- [x] `jda.toml` manifest file — name, version, dependencies, build config ✅
- [x] `jda pkg init` / `jda pkg add <name> <url> [tag]` / `jda pkg build` / `jda pkg deps` (`tools/jda-pkg.sh`) ✅
- [x] Git-based dependency resolution (tag-pinned versions, clone + checkout) ✅
- [x] Module system: dependency source concatenated before entry point from `jda.toml` deps ✅
- [x] Lockfile (`jda.lock`) — records name, tag, exact commit hash, URL for reproducible builds ✅
- [x] Docker-aware compilation (auto-detects macOS, uses jda-build container) ✅
- [x] 4 new conformance tests, 8 integration tests ✅
- [x] 158 total conformance tests, self-host converged at 1,964,161 bytes ✅

### M3: Language Server Protocol (LSP) ✅ COMPLETE

**Delivered (April 4, 2026):**
- [x] LSP server (`tools/jda-lsp.sh`) — Python-based, JSON-RPC 2.0 over stdio ✅
- [x] Go-to-definition — finds fn/struct/enum/const declarations ✅
- [x] Hover — keyword docs + user-defined function signatures ✅
- [x] Completion — keywords, symbols, variables in scope ✅
- [x] Diagnostics — tab detection, trailing whitespace warnings ✅
- [x] Document symbols — outline view for fn/struct/enum/const/impl ✅
- [x] Formatting — 4-space indent normalization ✅
- [x] Workspace symbol search ✅
- [x] VS Code extension (`tools/vscode-jda/`) — syntax highlighting, LSP client, language config ✅
- [x] TextMate grammar — keywords, types, builtins, strings, numbers, comments ✅
- [x] 4 new conformance tests, 8 LSP integration tests ✅
- [x] 162 total conformance tests, self-host converged at 1,964,161 bytes ✅

### M4: Formatter ✅ COMPLETE

**Delivered (April 4, 2026):**
- [x] `jda fmt` command (`tools/jda-fmt.sh`) — canonical formatting for all Jda source files ✅
- [x] Consistent 2-space indentation, opening brace on same line ✅
- [x] Single blank line between top-level declarations, collapse multiple blank lines ✅
- [x] Trailing whitespace removal, single trailing newline ✅
- [x] Comment preservation (full-line and inline) ✅
- [x] Idempotent: running twice produces identical output ✅
- [x] `jda fmt --check` for CI enforcement (exit 1 if unformatted) ✅
- [x] `jda fmt --diff` to preview changes ✅
- [x] `jda fmt --stdin` for pipe integration ✅
- [x] Directory recursive formatting ✅
- [x] 4 new conformance tests, 12 integration tests ✅
- [x] 166 total conformance tests, self-host converged at 1,964,161 bytes ✅

### M5: Documentation Generator ✅ COMPLETE

**Delivered (April 4, 2026):**
- [x] `jda doc` command (`tools/jda-doc.sh`) — extract `;;` doc comments and generate HTML ✅
- [x] Per-function, per-struct, per-enum, per-const documentation with signatures ✅
- [x] Multi-line doc comments joined into paragraphs ✅
- [x] Cross-referenced module index with navigation links ✅
- [x] Source file:line references on every item ✅
- [x] Static site output (index.html, module pages, style.css) — deployable to GitHub Pages ✅
- [x] Dark theme with Catppuccin-inspired color scheme ✅
- [x] `jda doc --json` for machine-readable output ✅
- [x] Directory recursive mode for multi-module projects ✅
- [x] 4 new conformance tests, 12 integration tests ✅
- [x] 170 total conformance tests, self-host converged at 1,964,161 bytes ✅

### M6: ARM64 Backend ✅ COMPLETE

**Delivered (April 4, 2026):**
- [x] ARM64 cross-compiler (`tools/jda-arm64.sh`) — Python-based, lexer + parser + AArch64 code generator ✅
- [x] AAPCS64 ABI — stp/ldp x29+x30 prologue/epilogue, x0-x7 args, frame pointer addressing ✅
- [x] Arithmetic operations — add, sub, mul, sdiv with register allocation ✅
- [x] Comparisons — cmp + cset for ==, !=, <, >, <=, >= ✅
- [x] Conditionals — cbz-based branching for if statements ✅
- [x] Function calls — bl instruction, args via x0-x7, multi-function programs ✅
- [x] Recursive functions — callee-saved frame with proper stack management ✅
- [x] String output — write syscall (#64) with adrp + add :lo12: PC-relative addressing ✅
- [x] Syscall support — number in x8, args in x0-x5, svc #0 ✅
- [x] Cross-assembly via Docker (aarch64-linux-gnu-as/ld) — produces valid aarch64 ELF binaries ✅
- [x] `--asm` mode for assembly inspection, `--run` mode for Docker-based execution ✅
- [x] 4 new conformance tests, 12 integration tests ✅
- [x] 174 total conformance tests, self-host converged at 1,964,161 bytes ✅

### M7: macOS Backend ✅ COMPLETE

**Delivered (April 4, 2026):**
- [x] macOS native compiler (`tools/jda-macos.sh`) — Python-based, lexer + parser + x86-64/ARM64 code generators ✅
- [x] x86-64 macOS codegen — System V AMD64 ABI, macOS syscalls with `0x2000000` prefix ✅
- [x] ARM64 macOS codegen — AAPCS64, macOS syscalls via x16 + `svc #0x80` ✅
- [x] Mach-O binary output via system assembler + linker (`as`, `ld`, `-lSystem`) ✅
- [x] Ad-hoc code signing (`codesign -s -`) — required for ARM64 macOS execution ✅
- [x] Universal binary support (`lipo -create`) — fat Mach-O with both architectures ✅
- [x] `--asm` mode for assembly inspection, `--arch` for target selection ✅
- [x] Function calls, arithmetic, comparisons, conditionals, recursion, strings, syscalls ✅
- [x] Native execution without Docker on macOS (both Intel and Apple Silicon) ✅
- [x] 4 new conformance tests, 12 integration tests ✅
- [x] 178 total conformance tests, self-host converged at 1,964,161 bytes ✅

### M8: WebAssembly Backend ✅ COMPLETE

**Delivered (April 4, 2026):**
- [x] WebAssembly compiler (`tools/jda-wasm.sh`) — Python-based, Jda → WAT → WASM pipeline ✅
- [x] WASI target — fd_write for stdout, proc_exit, runs on wasmtime/wasmer/Node.js ✅
- [x] Browser target — imports env.print_str, exports main + memory ✅
- [x] WAT text format output (`--wat`) for inspection and debugging ✅
- [x] WASM binary compilation via wat2wasm (wabt) or wasm-tools ✅
- [x] HTML playground generator (`--html`) — embedded WASM, Catppuccin dark editor, run button ✅
- [x] Linear memory model — string data segments at offset 1024, iov structs for fd_write ✅
- [x] i64 value types, LEB128 encoding, proper function type signatures ✅
- [x] Function calls, arithmetic, comparisons, conditionals, loops, recursion ✅
- [x] 4 new conformance tests, 12 integration tests ✅
- [x] 182 total conformance tests, self-host converged at 1,964,161 bytes ✅

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
