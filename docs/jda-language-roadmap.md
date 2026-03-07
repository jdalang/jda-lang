# Jda Language — Roadmap

**Build command:**
```
docker run --rm --platform linux/amd64 -v $(pwd):/jda -w /jda/bootstrap/stage0 jda-dev make clean all test stage1
```

**Current state (March 2026):**
- jda0 (5200+ lines NASM x86-64) → compiles jda1.jda → jda1 binary
- jda1 compiles: hello.jda, if/else programs, loop programs ✅
- Full pipeline: jda0 → jda1 → working ELF binaries on Linux x86-64
- Stage-0 pass-2 truncation blocker fixed (`P2 0` / 549-byte `jda1` issue resolved in `bootstrap/stage0/jda0.asm`) ✅
- 23 compiler bugs found and fixed (see `todo-compiler.md`)
- CI: Stage 0 smoke tests, conformance tests (24 pass / 2 fail), quality checks, self-host roundtrip gate

**What's working in jda0 (Stage 0 compiler):**
- [x] Struct definitions and struct arrays with field access
- [x] Let bindings, loops, if/else/else-if chains
- [x] Compound or/and conditions with short-circuit evaluation
- [x] Pointer deref read/write, address-of operator
- [x] Nested function calls (e.g., `emit_byte(out, pos, rex_byte(...))`)
- [x] Inline asm blocks
- [x] Struct literal init (`let x = Struct{}`)
- [x] 6-argument function calls (System V ABI)
- [x] mmap-based memory allocation for arrays

**What's working in jda1 (Stage 1 compiler — what jda1 can COMPILE):**
- [x] Lexer (all tokens, string/int literals, keywords)
- [x] Parser (fn, let, if/else, loop, print, return, expressions, assignment)
- [x] Function calls with arguments (`codegen_call` + `OP_CALL`)
- [x] JIR codegen (SSA instructions, basic blocks, branch/jump)
- [x] DCE (dead code elimination)
- [x] Constant folding
- [x] Register allocator (simple pool-based, spill to stack)
- [x] x86-64 lowering (MOV, ADD, SUB, MUL, CMP, JMP, Jcc, SETCC, PUSH/POP, CALL, SYSCALL)
- [x] Branch fixup patching (forward and backward jumps)
- [x] ELF64 writer (header + PT_LOAD + .text + .rodata)
- [x] String handling (inline strlen loop, strtab with RIP-relative LEA)
- [x] Loop variable mutation via stack slots (OP_STORE/OP_LOAD)

**What jda1 CANNOT compile yet (needed for self-hosting):**
- [ ] Array declarations and `arr[i]` / `arr[i].field` indexing
- [ ] Pointer/reference types (`&expr`, `ptr.field`, `&Type` in signatures)
- [ ] String escape sequences (`\n` → 0x0A in lexer)
- [ ] `print(int)` — only `print("string")` works
- [ ] `else if` chains (parser handles `else { }` but not `else if`)
- [ ] `const NAME = value` declarations from source
- [ ] `and` / `or` logical operators (no TOK_AND/TOK_OR in lexer)
- [ ] `>=` / `<=` comparison operators
- [ ] Inline `asm { }` blocks
- [ ] 5+ argument function calls (currently max 4 via operand0-3)

---

## Phase 1: Self-Hosting (jda1 compiles jda1.jda)

jda1 must support every feature used in its own source code (~1900 lines).

### 1. Multi-function programs
**Status:** ✅ DONE — **jda0: ✅ done | jda1: ✅ done**
**What:** jda1 now compiles programs with multiple `fn` definitions.
  - [x] Parse multiple `fn` definitions
  - [x] Emit separate function prologue/epilogue for each
  - [x] Lower OP_CALL → x86-64 `call rel32` instruction
  - [x] Argument passing: rdi, rsi, rdx (first 3 args via System V ABI)
  - [x] Return value in rax
  - [x] Function symbol table for call target resolution
**Why:** jda1.jda has 88+ functions.
**Branch:** `phase1-multi-function`

---

### 2. Struct definitions and field access
**Status:** ✅ DONE — **jda0: ✅ done | jda1: ✅ done (feature-complete)**
**Integration note (March 5, 2026):** `ci-selfhost-roundtrip` (`stage1_a -> stage1_b`) is still failing, but the remaining blocker is in other missing language features (notably `and`/`or` parsing), not in struct field access. Struct read/write/indexed-field matrix cases compile under stage1.
**Handoff note:** next issue owners should work `and`/`or` lexer+parser support (Phase 1 item 9). Current repro for the non-struct blocker: `if a == 1 or a == 2 { ... }` causes repeated parse errors and stage1 segfault; this is what currently prevents `ci-selfhost-roundtrip` from going green.
**What:**
  - [x] Parse `struct Name { field1: type  field2: type ... }`
  - [x] Calculate struct layout (field offsets, each field 8 bytes in jda)
  - [x] `s.field` → load from `base + offset`
  - [x] `s.field = val` → store to `base + offset`
  - [x] `arr[i].field` → base + (i * struct_size) + field_offset
  - [x] `&s` → address-of (LEA)
  - [x] Pass structs by reference (`fn foo(s: &Struct)`)
**Why:** jda1.jda uses 10+ structs: Token, Node, Instr, BasicBlock, JirFunction, RegAlloc, LowerCtx, Fixup, VarEntry, etc.

---

### 3. Array declarations and indexing
**Status:** [ ] TODO — **jda0: ✅ done | jda1: ❌ missing (alloc_pages used internally but no `Type[size]` syntax)**
**What:**
  - [ ] Parse `let arr = Type[size]` → mmap allocation
  - [ ] Parse `let arr = i64[size]` / `let arr = i32[size]` / `let arr = i8[size]`
  - [ ] `arr[i]` read → base + (i * element_size)
  - [ ] `arr[i] = val` write
  - [ ] `arr[i].field` for struct arrays
  - [ ] Stack-allocated small arrays vs mmap for large
**Why:** jda1.jda uses arrays everywhere (Token[4096], Instr[256], BasicBlock[64], etc.)

---

### 4. Pointer and reference support
**Status:** [ ] TODO — **jda0: ✅ done | jda1: ❌ missing**
**What:**
  - [ ] Parse `&expr` (address-of) → LEA
  - [ ] Parse `ptr[index]` (deref + index) → MOV from [base + index*stride]
  - [ ] Parse `ptr[0] = val` (deref + store)
  - [ ] Parse `&Type` in function signatures for pass-by-reference
  - [ ] Pointer arithmetic
**Why:** jda1.jda passes almost everything by pointer/reference.

---

### 5. String escape sequences
**Status:** ✅ DONE — **jda0: ✅ done | jda1: ✅ done**
**What:**
  - [x] `\n` → newline (0x0A)
  - [x] `\t` → tab (0x09)
  - [x] `\\` → backslash (0x5C)
  - [x] `\"` → quote (0x22)
  - [x] Process escapes when copying to strtab (emit_strlit)
  - [x] Lexer handles `\"` without terminating string early
**Why:** jda1.jda uses `\n` in print statements everywhere.
**Solution:** Use helper function `try_escape()` to work around jda0 codegen issue with if-statements in loops.
**Branch:** `issue-5-string-escape-sequences` ✅

---

### 6. print(int) — integer to string conversion
**Status:** [ ] TODO — **jda0: ✅ done | jda1: ❌ only print(string) works**
**What:**
  - [ ] Emit runtime int-to-decimal-string conversion
  - [ ] Handle negative numbers
  - [ ] Output via SYS_WRITE
**Why:** jda1.jda uses `print(variable)` for debug output of integer values.

---

### 7. Else-if chains
**Status:** [ ] TODO — **jda0: ✅ done | jda1: ❌ only if/else, not `else if`**
**What:**
  - [ ] Parse `if ... { } else if ... { } else { }` chains
  - [ ] Codegen cascading conditional branches
**Why:** jda1.jda uses many else-if chains (tokenizer keyword classification, op dispatch, etc.)

---

### 8. Constants (`const NAME = value`)
**Status:** [ ] TODO — **jda0: ✅ done | jda1: ❌ no `const` parsing from source**
**What:**
  - [ ] Parse `const NAME = int_literal`
  - [ ] Store in compile-time constant table
  - [ ] Resolve at codegen time (emit OP_CONST with stored value)
**Why:** jda1.jda has 40+ constants (TOK_*, NODE_*, OP_*, TYPE_*, PHYS_*, N_ALLOC_REGS, etc.)

---

### 9. Logical operators in expressions
**Status:** [ ] TODO — **jda0: ✅ done | jda1: ❌ no TOK_AND/TOK_OR/TOK_GE/TOK_LE in lexer**
**What:**
  - [ ] `and` / `or` in if/loop conditions with short-circuit evaluation
  - [ ] `!= null` null comparison
  - [ ] Chained conditions: `a >= '0' and a <= '9'`
**Why:** jda1.jda uses compound conditions in loops and if statements.

---

### 9a. Issue: stage1 roundtrip blocker (`and`/`or` crash)
**Status:** [ ] TODO — ISSUE TRACKER
**Problem:** `ci-selfhost-roundtrip` fails at `stage1_a -> stage1_b` because stage1 cannot parse logical operators used in `jda1.jda`, then segfaults in parse/codegen flow.
**Repro:**
  - [ ] `make ci-selfhost-roundtrip` fails with segfault in `stage1_a -> stage1_b`
  - [ ] Minimal repro: `if a == 1 or a == 2 { ... }` currently triggers repeated parse errors + segfault under stage1
**Scope:**
  - [ ] Add lexer tokens for `and` / `or` (and related `>=` / `<=` where needed)
  - [ ] Add parser precedence/associativity for logical operators
  - [ ] Implement lowering/codegen with short-circuit behavior
  - [ ] Ensure parse errors fail cleanly (no segfault) for malformed logical expressions
**Exit criteria:**
  - [ ] Minimal `and` / `or` conformance tests pass
  - [ ] `make ci-selfhost-roundtrip` passes stage1→stage1 compilation
**Owner handoff:** next contributor can start in `bootstrap/stage1/jda1.jda` (`classify_keyword`, lexer parse loop, `op_precedence`, `parse_binop`, `tok_to_jir_op`/control-flow lowering).

---

### 10. Self-hosting roundtrip
**Status:** [ ] TODO — MILESTONE 🎯
**What:** jda1 compiles jda1.jda → jda1-gen2 → compiles hello.jda → runs correctly. Binary hashes match.
**Depends on:** Items 1–9
**Why:** Once achieved, Jda compiler has zero external dependencies. The language bootstraps itself.

---

## Phase 2: Cross-Platform Installation

### 11. Linux x86-64 installer
**Status:** [ ] TODO
**What:**
  - [ ] Shell script: `curl -sSf https://jda-lang.org/install.sh | sh`
  - [ ] Downloads prebuilt `jda` binary to `~/.jda/bin/`
  - [ ] Adds to PATH via shell profile
  - [ ] `jda --version`, `jda build file.jda`, `jda run file.jda`
  - [ ] GitHub Releases with tarball
  - [ ] Optional: `.deb` and `.rpm` packages
**Why:** Primary platform. Must be one command to install.

---

### 12. macOS installer (arm64 + x86-64)
**Status:** [ ] TODO
**What:**
  - [ ] ARM64 code generation backend (Apple Silicon)
  - [ ] Mach-O binary format (replace ELF)
  - [ ] macOS syscall numbers and ABI
  - [ ] `brew install jda` (Homebrew formula)
  - [ ] Shell installer for macOS
  - [ ] Universal binary or architecture detection
**Ref:** `targets/arm64.jda` has initial spec
**Why:** Majority of developers use macOS.

---

### 13. Windows installer
**Status:** [ ] TODO
**What:**
  - [ ] PE/COFF binary format (replace ELF)
  - [ ] Windows calling convention (rcx, rdx, r8, r9)
  - [ ] Win32 API or NT syscalls
  - [ ] `winget install jda` or `scoop install jda`
  - [ ] MSI installer
  - [ ] PowerShell install script
**Ref:** `targets/windows.jda` has initial spec
**Why:** Enterprise adoption requires Windows.

---

### 14. WebAssembly target
**Status:** [ ] TODO
**What:**
  - [ ] WASM binary emission
  - [ ] WASI support for I/O
  - [ ] `jda build --target wasm`
  - [ ] Browser playground on website
**Ref:** `targets/wasm.jda` has initial spec
**Why:** Web deployment, serverless, browser playground for learning.

---

## Phase 3: Language Features (Competitive Parity)

### 15. Type system and type checking
**Status:** [ ] TODO
**What:**
  - [ ] Type inference for `let` bindings
  - [ ] Function parameter and return type checking
  - [ ] Struct field type checking
  - [ ] Pointer/reference type tracking
  - [ ] Clear error messages with source location
**Why:** Without type checking, programs silently produce wrong results.

---

### 16. Enums and pattern matching
**Status:** [ ] TODO
**What:**
  - [ ] `enum Shape { Circle(f64)  Rect(f64, f64) }`
  - [ ] `match expr { Pattern => body ... }`
  - [ ] Exhaustiveness checking
  - [ ] Tagged union codegen
**Why:** Advertised in README. Used for Result<T,E> error handling.

---

### 17. Result<T,E> error handling
**Status:** [ ] TODO
**What:**
  - [ ] Built-in `Result<T, E>` type
  - [ ] `ok(val)` and `err(msg)` constructors
  - [ ] `?` operator for early return on error
  - [ ] No exceptions — errors are values
**Why:** Jda's error model. Every stdlib function should return Result.

---

### 18. Generics (parametric polymorphism)
**Status:** [ ] TODO
**What:**
  - [ ] `fn foo<T>(x: T) -> T`
  - [ ] `struct Vec<T> { ... }`
  - [ ] Monomorphization (one copy per concrete type)
**Why:** Required for generic containers (Vec, HashMap, Option, Result).

---

### 19. impl blocks and methods
**Status:** [ ] TODO
**What:**
  - [ ] `impl Struct { fn method(self, ...) ... }`
  - [ ] Method call: `obj.method(args)`
  - [ ] `self` as implicit first parameter
**Why:** In syntax spec and README. Core ergonomic.

---

### 20. Traits / interfaces
**Status:** [ ] TODO
**What:**
  - [ ] `trait Name { fn method(self, ...) ... }`
  - [ ] `impl Trait for Struct { ... }`
  - [ ] Trait bounds: `fn foo<T: Display>(x: T)`
  - [ ] Optional vtable-based dynamic dispatch
**Why:** Required for polymorphism, operator overloading, standard traits (Display, Iterator, etc.)

---

### 21. Ownership and borrow checking
**Status:** [ ] TODO
**What:**
  - [ ] Track heap allocation ownership at compile time
  - [ ] Enforce single-owner rule
  - [ ] Borrow checker: no aliased mutable references
  - [ ] Lifetime annotations
  - [ ] Automatic drop/deallocation at scope exit
**Ref:** `mem/` has the model designed
**Why:** "Safe like Rust" is Jda's core promise. Must be enforced by compiler.

---

## Phase 4: Standard Library

### 22. Core standard library
**Status:** [ ] TODO (spec .jda files exist in `stdlib/`)
**What:**
  - [ ] `fmt` — string formatting: `fmt("x = {}", x)`
  - [ ] `fs` — file read/write/stat/mkdir
  - [ ] `io` — buffered reader/writer, stdin/stdout
  - [ ] `collections` — Vec, HashMap, HashSet, Queue, Stack
  - [ ] `math` — sqrt, sin, cos, pow, log, abs, min, max
  - [ ] `strings` — split, trim, contains, replace, to_upper/lower
  - [ ] `net` — TCP/UDP sockets, HTTP client and server
  - [ ] `json` — parse and emit JSON
  - [ ] `time` — timestamps, duration, sleep, timer
  - [ ] `crypto` — SHA256, HMAC, random
  - [ ] `process` — spawn, pipe, exec, env vars
  - [ ] `regex` — regular expression matching
  - [ ] `os` — platform detection, args, exit
**Why:** A language without stdlib is unusable for real work.

---

## Phase 5: Developer Tooling

### 23. CLI interface (`jda` command)
**Status:** [ ] TODO
**What:**
  - [ ] `jda build file.jda` — compile to binary
  - [ ] `jda run file.jda` — compile and run
  - [ ] `jda test` — discover and run test functions
  - [ ] `jda fmt` — format source code
  - [ ] `jda doc` — generate API documentation
  - [ ] `jda version` — show version
  - [ ] `jda init` — create new project
**Why:** Single entry point like `go`, `cargo`, `python`.

---

### 24. Package manager (`jda pkg`)
**Status:** [ ] TODO (spec at `tools/pkg.jda`)
**What:**
  - [ ] `jda pkg init` — create project manifest
  - [ ] `jda pkg add <name>` — add dependency
  - [ ] `jda pkg build` — build with dependencies
  - [ ] `jda pkg publish` — publish to registry
  - [ ] Package registry website
  - [ ] Lock file for reproducible builds
  - [ ] Semantic versioning
**Why:** Go has `go mod`, Rust has `cargo`, Node has `npm`.

---

### 25. Built-in test framework
**Status:** [ ] TODO
**What:**
  - [ ] `test fn test_name() { ... }` or `#[test]` attribute
  - [ ] `jda test` discovers and runs all tests
  - [ ] `assert(cond)`, `assert_eq(a, b)`, `assert_ne(a, b)`
  - [ ] Pass/fail counts, failure details with source location
  - [ ] Parallel test execution
**Why:** `go test` and `cargo test` are huge productivity wins.

---

### 26. Formatter (`jda fmt`)
**Status:** [ ] TODO
**What:**
  - [ ] Canonical style: indentation, spacing, alignment
  - [ ] `jda fmt` reformats in-place
  - [ ] `jda fmt --check` for CI
  - [ ] Zero configuration — one style (like `gofmt`)
**Why:** Eliminates style debates. CI-enforceable.

---

### 27. LSP server and IDE support
**Status:** [ ] TODO (spec at `tools/lsp.jda`)
**What:**
  - [ ] Go-to-definition, hover info, autocomplete
  - [ ] Error diagnostics (inline)
  - [ ] Rename symbol
  - [ ] VS Code extension on marketplace
  - [ ] Neovim/Emacs LSP support
**Why:** Modern development requires IDE intelligence.

---

### 28. Debugger support
**Status:** [ ] TODO
**What:**
  - [ ] DWARF debug info in ELF binaries
  - [ ] Source-level debugging with GDB/LLDB
  - [ ] Breakpoints, step, inspect variables
  - [ ] Stack trace on crash with source locations
**Why:** Essential for debugging. C has had this for 40 years.

---

### 29. REPL / interactive mode
**Status:** [ ] TODO
**What:**
  - [ ] `jda repl` — interactive expression evaluation
  - [ ] Define functions, inspect results
  - [ ] Tab completion, history
**Why:** Python/Ruby developers expect this. Great for learning.

---

## Phase 6: Documentation

### 30. Language reference manual
**Status:** [ ] TODO
**What:**
  - [ ] Complete grammar (EBNF or railroad diagrams)
  - [ ] All types: primitives, structs, enums, arrays, pointers, references
  - [ ] All statements: let, if, loop, match, ret, fn, struct, enum, impl, trait
  - [ ] Operators (left-to-right evaluation, no precedence — Jda design)
  - [ ] Ownership and borrowing rules
  - [ ] Memory model
  - [ ] Calling conventions
**Where:** `docs/reference/` and website

---

### 31. Getting Started tutorial
**Status:** [ ] TODO
**What:**
  - [ ] Install (one-liner per OS)
  - [ ] Hello World
  - [ ] Variables, types, functions
  - [ ] Structs and methods
  - [ ] Control flow (if/else, loop, match)
  - [ ] Error handling (Result)
  - [ ] Build a small project (CLI tool or web server)
**Where:** `docs/tutorial/` and website

---

### 32. API documentation (auto-generated)
**Status:** [ ] TODO
**What:**
  - [ ] Doc comments in source (`; @doc ...` or `/// ...`)
  - [ ] `jda doc` generates HTML
  - [ ] Every public function: signature, description, example
  - [ ] Searchable website (like docs.rs / pkg.go.dev)

---

### 33. Examples and cookbook
**Status:** [ ] PARTIAL (4 examples: hello.jda, web_server.jda, mlp.jda, transformer.jda)
**What:** Expand `examples/` with real-world programs:
  - [ ] CLI argument parser
  - [ ] File I/O (read CSV, write JSON)
  - [ ] HTTP server and client
  - [ ] WebSocket chat
  - [ ] Concurrent worker pool
  - [ ] ML inference
  - [ ] Game of Life (terminal)
  - [ ] Markdown to HTML
  - [ ] Build tool / task runner
  - [ ] Key-value store

---

### 34. Website (jda-lang.org)
**Status:** [ ] TODO
**What:**
  - [ ] Landing page with elevator pitch
  - [ ] Install instructions (Linux/macOS/Windows)
  - [ ] Online playground (WASM)
  - [ ] Documentation hub
  - [ ] Blog
  - [ ] Package registry search

---

## Phase 7: Performance and Production

### 35. Optimizing compiler backend
**Status:** [ ] PARTIAL (basic DCE + constant folding done)
**What:**
  - [ ] Graph-coloring register allocator
  - [ ] Instruction selection (not 1:1 IR → x86)
  - [ ] Function inlining
  - [ ] Loop unrolling
  - [ ] Tail call optimization
  - [ ] Benchmark suite (Jda vs C vs Go vs Rust)

---

### 36. Concurrency runtime (J-Threads)
**Status:** [ ] TODO (spec at `concurrency/`)
**What:**
  - [ ] Green thread scheduler (M:N)
  - [ ] Lock-free channels
  - [ ] `spawn` keyword, channel send/recv
  - [ ] Work-stealing scheduler
  - [ ] Deadlock detection
**Why:** "Concurrent like Go" promise.

---

### 37. ML runtime (tensors, autograd)
**Status:** [ ] TODO (spec at `stdlib/ml/`)
**What:**
  - [ ] Tensor as language primitive
  - [ ] Compile-time shape checking
  - [ ] Autograd (reverse-mode AD)
  - [ ] GPU backends (CUDA, ROCm, Metal)
  - [ ] SIMD acceleration (AVX-512, NEON)
**Why:** "ML-native" unique differentiator.

---

### 38. C FFI (Foreign Function Interface)
**Status:** [ ] TODO
**What:**
  - [ ] Call C functions from Jda
  - [ ] Expose Jda functions to C
  - [ ] C header parser (basic)
  - [ ] libc interop layer (optional)
**Why:** No language succeeds in isolation. Must use existing C libraries.

---

## Competitor Comparison

| Feature | C | Go | Rust | Python | Ruby | **Jda** |
|---------|---|-----|------|--------|------|---------|
| Cross-platform | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ Linux x86-64 only |
| Self-hosted | ✅ | ✅ | ✅ (LLVM) | N/A | N/A | 🔧 In progress |
| Package manager | cmake | go mod | cargo | pip | gem | ❌ Spec only |
| Test framework | external | go test | cargo test | pytest | minitest | ❌ |
| Formatter | clang-format | gofmt | rustfmt | black | rubocop | ❌ |
| Debugger | GDB | dlv | rust-gdb | pdb | byebug | ❌ |
| IDE/LSP | clangd | gopls | rust-analyzer | pylsp | solargraph | ❌ Spec only |
| REPL | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ |
| Generics | templates | ✅ | ✅ | ✅ | duck typing | ❌ |
| Error handling | errno | error | Result<T,E> | exceptions | exceptions | ❌ |
| Concurrency | pthreads | goroutines | async/tokio | asyncio | threads | ❌ Spec only |
| ML native | ❌ | ❌ | ❌ | PyTorch/NumPy | ❌ | ❌ Spec only |
| Zero deps compiler | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ NASM → bare metal |
| Docs/website | cppreference | go.dev | rust-lang.org | python.org | ruby-lang.org | jdalang.org |

---

## Priority Order

**P0 — Blocks everything:**
1. Multi-function (#1) → Structs (#2) → Arrays (#3) → Pointers (#4) → Self-hosting (#10)

**P1 — Blocks adoption:**
2. Linux installer (#11) → macOS (#12) → Windows (#13)
3. Tutorial (#31) → Language reference (#30)
4. Type checking (#15) → Error handling (#17)

**P2 — Competitive parity:**
5. Package manager (#24) → Test framework (#25) → Formatter (#26)
6. Enums (#16) → Generics (#18) → Traits (#20)
7. LSP + VS Code extension (#27)
8. Website (#34)

**P3 — Differentiation:**
9. J-Threads concurrency (#36)
10. ML tensor runtime (#37)
11. Debugger (#28) → REPL (#29)
12. C FFI (#38) → WASM (#14)
