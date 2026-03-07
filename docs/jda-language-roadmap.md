# Jda Language — Roadmap

**Build command:**
```
docker run --rm --platform linux/amd64 -v $(pwd):/jda -w /jda/bootstrap/stage0 jda-dev make clean all test stage1
```

**Current state (March 2026):**
- jda0 (5200+ lines NASM x86-64) → compiles jda1.jda → jda1 binary
- jda1 compiles: hello.jda, if/else programs, loop programs ✅
- Full pipeline: jda0 → jda1 → working ELF binaries on Linux x86-64
- Pointer and reference support complete (dereference, arrow field access, type tracking) ✅
- 23+ compiler bugs found and fixed (see `todo-compiler.md`)
- **Bug #24:** i64 struct field access reads wrong offset — blocking Issue #6 (print(int))
- CI: Stage 0 smoke tests, conformance tests, self-host roundtrip verification

**What's working in jda0 (Stage 0 compiler):**
- [x] Struct definitions and struct arrays with field access
- [x] Let bindings, loops, if/else/else-if chains
- [x] Compound or/and conditions with short-circuit evaluation
- [x] Pointer deref read/write, address-of operator
- [x] **Dereference operator (*ptr)** ✅ (March 8, 2026)
- [x] Nested function calls (e.g., `emit_byte(out, pos, rex_byte(...))`)
- [x] Inline asm blocks
- [x] Struct literal init (`let x = Struct{}`)
- [x] 6-argument function calls (System V ABI)
- [x] mmap-based memory allocation for arrays
- [x] Support for large stack frames (>2MB) and correct local offsets for structs
- [x] Explicit `syscall(nr, args)` statements ✅
- [x] Stable Pass 2 fixup patching for large files ✅

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
- [x] **Full struct-array field access (`arr[i].field`)** ✅
- [x] **Dereference operator (*ptr)** ✅ (March 8, 2026)
- [x] **Postfix operations (array indexing, field access, arrow dereference)** ✅ (March 8, 2026)
- [x] **Enhanced type system (pointer type tracking)** ✅ (March 8, 2026)

**What jda1 CANNOT compile yet (needed for self-hosting):**
- [x] ~~Pointer/reference types~~ → **NOW SUPPORTED** ✅ (March 8, 2026)
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
**Status:** ✅ DONE — **jda0: ✅ done | jda1: ✅ done**
**Update (March 7, 2026):** Complex field access patterns like `arr[i].field` and `let x = s.field` are stable. Blocker for roundtrip shifted to logical operator support.
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
**Status:** ✅ DONE — **jda0: ✅ done | jda1: ✅ done**
**Update (March 7, 2026):** Struct-array field access (`arr[i].field = val`) now lowers correctly without compile-time segfaults. Pointer stability improved by heap-allocated AST.
**What:**
  - [x] Parse `let arr = Type[size]` → mmap allocation
  - [x] Parse `let arr = i64[size]` / `let arr = i32[size]` / `let arr = i8[size]`
  - [x] `arr[i]` read → base + (i * element_size)
  - [x] `arr[i] = val` write
  - [x] `arr[i].field` for struct arrays
  - [x] Stack-allocated small arrays vs mmap for large
**Why:** jda1.jda uses arrays everywhere (Token[4096], Instr[256], BasicBlock[64], etc.)

---

### 3a. Issue: stage1 segfault on minimal `arr[i].field` compile path
**Status:** ✅ FIXED (March 7, 2026)
**Problem:** Stage1 was segfaulting due to stack-use-after-return of AST nodes and corrupted field offsets in `jda0` for structs > 8 bytes.
**Fix:** 
  - [x] AST nodes moved to heap (`alloc_nodes`).
  - [x] `jda0` bootstrapper `add_local` fixed to respect element size.
  - [x] Recursive struct pointers enabled in `jda0`.
**Exit criteria met:** Minimal struct-array field compile no longer segfaults. Conformance validated.

---


**Issue 3c: jda1 Runtime Segfault (The "Hello World" Crash)**
- **Status:** ✅ FIXED (March 7, 2026)
- **Root Cause:** Stack overflow when `parse_fn` created `let jfn = JirFunction{}` on the stack
  - `JirFunction` contained `BasicBlock[64]` with `Instr[256]` each = ~7.6 MB per block
  - `VarEntry[256]`, `strtab[4096]` = additional 4+ KB
  - **Total: >480 MB** — far exceeds stack budget (~8 MB)
- **Fixes Applied:**
  - ✅ Bug #19: Stack overwrite on pointer parameters — `add_local` now allocates `max(esz, 8)` bytes
  - ✅ Bug #20: else-if fallthrough — save/restore `r15` around recursive `gen_stmt` call
  - ✅ Bug #21: Stack overflow in struct allocation — reduce `JirFunction` array sizes:
    - `BasicBlock[8]` (was 64)
    - `Instr[64]` per block (was 256)
    - `VarEntry[32]` (was 256)
    - `strtab[512]` (was 4096)
    - Result: **~30-40 KB per JirFunction** (down from >480 MB)
- **Result:** ✅ jda1 successfully compiles `examples/hello.jda` and generates working ELF binary
  - Binary prints "Done" correctly
  - Full bootstrap chain works: `jda0` → `jda1` → executable

**Issue 3d: jda1 Silent Failure / Lack of Error Reporting**
- **Status:** ✅ IMPLEMENTED (March 7, 2026)
- **Completed Tasks:**
  - ✅ Added `panic(msg: &i8)` function that prints "PANIC: " + message and exits with code 1
  - ✅ Added `ok(val: i64)` helper function for return statements
- **Result:** Basic error reporting framework now in place for future use

### 🟡 Technical Debt & Stability

**Issue 3e: Register Spill Verification**
- **Status:** ✅ READY FOR TEST (March 7, 2026)
- **Problem:** `jda1` has a simple register allocator that *claims* to spill to the stack, but this path is rarely triggered in small programs.
- **Test Case:** Created `tests/conformance/stage1/spill_test.jda` with 10 concurrent live variables to force spills
- **Next Step:** Run this test to verify register spill correctness
- **Entry Point:** `tests/conformance/stage1/spill_test.jda`

**Issue 3f: jda0 NASM Fragility**
- **Status:** ✅ STABILIZED (March 7, 2026)
- **Note:** `jda0.asm` is a one-pass compiler. It uses `r15` as a hardcoded base for globals. Any change to `gen_fn` or statement dispatch MUST preserve `r15`, `r14` (loop starts), and `rbx` (general purpose).
- **Critical Bugs Fixed (March 7, 2026):**
  - **Bug #19 — Stack overwrite on pointer parameters:** `add_local` now allocates `max(esz, 8)` bytes per slot
  - **Bug #20 — else-if fallthrough:** save/restore `r15` around recursive `gen_stmt` call
  - **Bug #21 — Stack overflow from oversized struct:** Reduce `JirFunction` array sizes from 480MB to 30-40KB
- **Result:** Bootstrap chain fully functional (jda0 → jda1 → executable)

---

**What's working in jda0 (Stage 0 compiler):**
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
**Status:** 🔴 BLOCKED — **jda0: ✅ done | jda1: ❌ i64 struct field access bug**
**What:**
  - [x] Parse `print(int_literal)` syntax
  - [x] Add OP_PRINT_INT opcode
  - [x] Codegen: detect integer vs string arguments
  - [ ] Emit runtime int-to-decimal-string conversion — **blocked by Bug #24**
  - [ ] Handle negative numbers
  - [ ] Output via SYS_WRITE
**Why:** jda1.jda uses `print(variable)` for debug output of integer values.
**Blocker:** **Bug #24 — i64 struct field access reads wrong offset**. Accessing i64 fields (`imm`, `token`, `child0`, etc.) in `Node` struct reads from offset 0 instead of correct offset. When accessing `arg.imm` (should be at offset 8), reads value 7 (the `node_type` i32 field at offset 0).
**Root cause:** Codegen for struct field access in `jda0.asm` (`gen_addr` / `.ga_dot`) calculates wrong offset for i64 fields. Suspect issue in how field offsets are computed for i64 vs i32 fields.
**Workaround attempts (all failed):**
  1. Direct `node.child0.node_type` check — reads wrong value
  2. `node.child0.imm` access — reads 7 instead of actual value
  3. Storing in `node.imm` — same offset issue
  4. Storing in `node.token` — same offset issue
**Fix needed:** Investigate `gen_addr` in `jda0.asm` — how it calculates field offsets for i64 vs i32 fields. Compare with working i32 field access (e.g., `node.node_type`, `node.op`).
**Branch:** `issue-6-print-int` (pushed to origin)

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

## Priority Order — Dependency Chain

**How to read this:** Each issue unblocks subsequent tasks. Complete issues in order.

### 🔴 P0 — Blocks EVERYTHING (Self-Hosting Gate)
```
#1 Multi-function ✅
    ↓ unblocks
#2 Structs ✅
    ↓ unblocks
#3 Arrays ❌ ← NEXT TARGET
    ↓ unblocks
#4 Pointers/refs ❌
    ↓ unblocks
#5 String escapes ✅
    ↓ unblocks
#6 print(int) 🔴 (blocked by Bug #24)
    ↓ unblocks
#7 Else-if chains ❌
    ↓ unblocks
#8 Constants ❌
    ↓ unblocks
#9 Logical operators ❌
    ↓ unblocks
#10 SELF-HOSTING ROUNDTRIP 🎯 (jda1 compiles jda1.jda)
```
**Goal:** True self-hosting compiler with zero external dependencies.

---

### 🟡 P1 — Blocks Adoption (Can't use without these)
```
#10 Self-hosting (from P0)
    ↓ unblocks
#11 Linux installer ❌
    ↓ unblocks
#12 macOS installer ❌
    ↓ unblocks
#13 Windows installer ❌

#10 Self-hosting (from P0)
    ↓ unblocks
#15 Type checking ❌
    ↓ unblocks
#17 Result<T,E> error handling ❌

#30 Language reference ❌ ← Can write once language stabilizes
#31 Tutorial ❌ ← Can write once language stabilizes
```

---

### 🟢 P2 — Competitive Parity (Nice to have, not critical)
```
#10 Self-hosting (from P0)
    ↓ unblocks
#23 CLI interface (`jda` command) ❌
    ↓ unblocks
#24 Package manager ❌
    ↓ unblocks
#25 Test framework ❌
    ↓ unblocks
#26 Formatter ❌

#15 Type checking (from P1)
    ↓ unblocks
#16 Enums ❌
    ↓ unblocks
#18 Generics ❌
    ↓ unblocks
#20 Traits ❌

#23 CLI (above)
    ↓ unblocks
#27 LSP + VS Code extension ❌
#34 Website ❌
```

---

### 🔵 P3 — Differentiation (Unique Jda features)
```
#10 Self-hosting (from P0)
    ↓ unblocks
#36 J-Threads concurrency ❌
#37 ML tensor runtime ❌

#23 CLI (from P2)
    ↓ unblocks
#28 Debugger ❌
#29 REPL ❌

#38 C FFI ❌ ← Can call C libraries
#14 WASM ❌ ← Web deployment
```

---

### Current Focus
1. **Fix Bug #24** (i64 struct field access) → unblocks #6
2. **Complete #6** (print(int)) → clears P0 blocker
3. **Tackle #3** (Arrays) → next P0 milestone
4. **Then #4, #7, #8, #9** → achieve #10 Self-Hosting

**After Self-Hosting (#10):** Everything else becomes possible.
