# Jda Language — Post-Bootstrap Roadmap

**Goal:** Take Jda from a working bootstrap compiler to a complete, installable, documented language that developers can use on Linux, macOS, and Windows.

**Current state:** jda0 (NASM) → compiles jda1.jda → jda1 binary → compiles hello.jda + if/else programs. Self-hosting bootstrap chain works end-to-end on Linux x86-64.

---

## Phase 1: Complete the Compiler (Self-Hosting Parity)

These items are required before jda1 can compile itself (full self-hosting).

### 1. Loop variable mutation — SSA stack-slot approach
**Status:** [ ] TODO
**File:** `bootstrap/stage1/jda1.jda`
**What:** `i = i + 1` inside loops crashes because jda1 uses SSA without phi nodes. Need to switch mutable variables from SSA registers to stack-slot based OP_STORE/OP_LOAD.
**Why:** Loops are fundamental — no useful program works without them.
**Ref:** todo-compiler.md Bug #23

---

### 2. Function calls (multi-function programs)
**Status:** [ ] TODO
**File:** `bootstrap/stage1/jda1.jda` — OP_CALL lowering
**What:** jda1 currently only compiles single-function programs (`fn main()`). Need to:
  - Lower OP_CALL to x86-64 `call` instruction
  - Emit function prologues/epilogues for each function
  - Handle argument passing (System V ABI: rdi, rsi, rdx, rcx, r8, r9)
  - Handle return values (rax)
**Why:** Self-hosting requires jda1 to call its own functions (parse, codegen, lower, etc.)

---

### 3. Struct support in jda1
**Status:** [ ] TODO
**What:** jda1 needs to parse and codegen struct definitions, field access, and struct-as-arguments.
  - [ ] Parse `struct Name { field: type ... }`
  - [ ] Calculate struct layout (field offsets, total size)
  - [ ] Codegen field access (`s.field` → load from base+offset)
  - [ ] Pass structs by reference (`&Struct`)
**Why:** jda1.jda itself uses 10+ structs (Token, Node, Instr, BasicBlock, etc.)

---

### 4. Array support in jda1
**Status:** [ ] TODO
**What:** jda1 needs to handle array declarations and indexing.
  - [ ] Parse `let arr = Type[size]` (mmap allocation)
  - [ ] Codegen `arr[i]` read/write
  - [ ] Codegen `arr[i].field` for struct arrays
**Why:** jda1.jda uses arrays everywhere (Token[4096], Instr[256], etc.)

---

### 5. String handling improvements
**Status:** [ ] TODO
**What:**
  - [ ] Escape sequences (`\n`, `\t`, `\\`) in string literals
  - [ ] String concatenation or formatting
  - [ ] print(int) — emit integer-to-string conversion at runtime
**Why:** Debugging output and user-facing programs need formatted strings.

---

### 6. Pointer/reference support in jda1
**Status:** [ ] TODO
**What:**
  - [ ] Parse `&expr` (address-of)
  - [ ] Parse `ptr[0]` (deref with index)
  - [ ] Parse `&Type` in function parameter types
  - [ ] Codegen LEA for address-of, MOV for dereference
**Why:** jda1.jda passes most structs and arrays by pointer.

---

### 7. Re-enable and verify fold_constants
**Status:** [ ] TODO
**What:** fold_constants struct-by-value was fixed but the function is still disabled. Uncomment, test, verify no regressions.
**Why:** Constant folding is needed for performance and correctness of compiled programs.

---

### 8. Self-hosting roundtrip: jda1 compiles jda1.jda
**Status:** [ ] TODO — MILESTONE
**What:** jda1 binary successfully compiles its own source code, producing jda1-gen2, which also compiles hello.jda correctly. Binary hashes of gen1 and gen2 should match (deterministic output).
**Depends on:** Items 1–6 above
**Why:** This is the primary bootstrap goal. Once achieved, Jda no longer depends on NASM/x86 assembly.

---

## Phase 2: Cross-Platform Support

### 9. Linux x86-64 installer
**Status:** [ ] TODO
**What:**
  - [ ] Shell install script: `curl -sSf https://jda-lang.org/install.sh | sh`
  - [ ] Downloads prebuilt jda binary to `~/.jda/bin/`
  - [ ] Adds to PATH via `.bashrc` / `.zshrc`
  - [ ] `jda --version` works out of the box
  - [ ] Tarball release on GitHub Releases
**Why:** Primary development platform. Must be friction-free.

---

### 10. macOS support (arm64 + x86-64)
**Status:** [ ] TODO
**What:**
  - [ ] arm64 backend in jda1 (Apple Silicon is dominant now)
  - [ ] Mach-O binary format emission (replace ELF)
  - [ ] macOS syscall ABI (different numbers, different conventions)
  - [ ] Universal binary or separate arm64/x86-64 builds
  - [ ] Homebrew formula: `brew install jda`
  - [ ] Shell installer for macOS
**Ref:** `targets/arm64.jda` exists but needs integration with jda1
**Why:** Large developer population on macOS.

---

### 11. Windows support
**Status:** [ ] TODO
**What:**
  - [ ] PE/COFF binary format emission (replace ELF)
  - [ ] Windows syscall ABI (Win32 API or NT syscalls)
  - [ ] Windows calling convention (rcx, rdx, r8, r9 — different from SysV)
  - [ ] MSI or scoop/winget installer
  - [ ] PowerShell install script
**Ref:** `targets/windows.jda` exists but needs integration with jda1
**Why:** Huge user base. Enterprise adoption requires Windows support.

---

### 12. WebAssembly target
**Status:** [ ] TODO
**What:**
  - [ ] WASM binary emission from jda1
  - [ ] WASI support for filesystem/networking
  - [ ] Browser-runnable Jda programs
  - [ ] `jda build --target wasm` flag
**Ref:** `targets/wasm.jda` exists but needs integration
**Why:** Web deployment, serverless edge computing, playground.

---

## Phase 3: Language Features (Competitive Parity)

What C/Go/Rust/Python developers expect from a modern language.

### 13. Type system and type checking
**Status:** [ ] TODO
**What:**
  - [ ] Type inference for `let` bindings
  - [ ] Function signature type checking (params + return)
  - [ ] Struct field type checking
  - [ ] Pointer/reference type tracking
  - [ ] Clear error messages for type mismatches
**Why:** Every modern language has type checking. Without it, programs silently produce wrong results.

---

### 14. Ownership and borrow checking
**Status:** [ ] TODO
**What:**
  - [ ] Track ownership of heap allocations
  - [ ] Enforce single-owner rule at compile time
  - [ ] Borrow checker: no aliased mutable references
  - [ ] Lifetime annotations for references
**Ref:** `mem/` has the model spec'd; needs compiler enforcement
**Why:** Jda's value proposition is "safe like Rust" — must deliver on this.

---

### 15. Enums and pattern matching
**Status:** [ ] TODO
**What:**
  - [ ] Parse `enum Name { Variant1(types) Variant2 ... }`
  - [ ] Parse `match expr { Pattern => body ... }`
  - [ ] Exhaustiveness checking
  - [ ] Codegen for tagged unions
**Ref:** Already in syntax spec and README examples
**Why:** Core language feature promised in docs. Used for error handling (Result<T, E>).

---

### 16. Error handling (Result type)
**Status:** [ ] TODO
**What:**
  - [ ] Built-in `Result<T, E>` type
  - [ ] `?` operator for early return on error
  - [ ] `ok(val)` and `err(msg)` constructors
  - [ ] No exceptions — errors are values
**Why:** Every Jda function signature in jda1.jda uses `-> Result` or returns error codes.

---

### 17. Generics / parametric polymorphism
**Status:** [ ] TODO
**What:**
  - [ ] Parse `fn foo<T>(x: T) -> T`
  - [ ] Monomorphization (one copy per concrete type)
  - [ ] Generic structs: `struct Vec<T> { ... }`
**Why:** Required for generic data structures (Vec, HashMap, Result, Option).

---

### 18. impl blocks and methods
**Status:** [ ] TODO
**What:**
  - [ ] Parse `impl StructName { fn method(self, ...) ... }`
  - [ ] Method call syntax: `obj.method(args)`
  - [ ] `self` as implicit first parameter
**Why:** In syntax spec and README examples. Core OOP-like ergonomic.

---

### 19. Traits / interfaces
**Status:** [ ] TODO
**What:**
  - [ ] Parse `trait Name { fn method(self, ...) ... }`
  - [ ] `impl Trait for Struct { ... }`
  - [ ] Trait bounds on generics: `fn foo<T: Display>(x: T)`
  - [ ] Dynamic dispatch via vtables (optional)
**Why:** Required for polymorphism. Rust/Go both have this.

---

### 20. Standard library — core modules
**Status:** [ ] PARTIAL (spec files exist, no compiled implementation)
**What:**
  - [ ] `fmt` — string formatting, print with args: `fmt("x = {}", x)`
  - [ ] `fs` — file read/write/seek/stat
  - [ ] `net` — TCP/UDP sockets, HTTP client/server
  - [ ] `json` — parse and emit JSON
  - [ ] `time` — timestamps, durations, sleep
  - [ ] `crypto` — hashing (SHA256, etc.)
  - [ ] `process` — spawn, pipe, exec
  - [ ] `collections` — Vec, HashMap, HashSet, Queue
  - [ ] `io` — buffered reader/writer
  - [ ] `regex` — regular expressions
  - [ ] `math` — sqrt, sin, cos, pow, log, etc.
**Ref:** `stdlib/` has .jda spec files for many of these
**Why:** A language without a usable stdlib is a toy.

---

## Phase 4: Developer Tooling

### 21. Package manager (`jda pkg`)
**Status:** [ ] TODO (spec at `tools/pkg.jda`)
**What:**
  - [ ] `jda pkg init` — create new project
  - [ ] `jda pkg add <name>` — add dependency
  - [ ] `jda pkg build` — build project
  - [ ] `jda pkg test` — run tests
  - [ ] `jda pkg publish` — publish to registry
  - [ ] Package registry website (like crates.io / pkg.go.dev)
  - [ ] Lock file for reproducible builds
**Why:** Go has `go mod`, Rust has `cargo`, Node has `npm`. Essential for ecosystem.

---

### 22. Built-in test framework
**Status:** [ ] TODO
**What:**
  - [ ] `test` keyword or `#[test]` attribute for test functions
  - [ ] `jda test` command to discover and run all tests
  - [ ] Assert macros: `assert(cond)`, `assert_eq(a, b)`
  - [ ] Test output: pass/fail counts, failure details
  - [ ] Parallel test execution
**Why:** Go's `go test` is a huge productivity win. Every modern language has this.

---

### 23. Formatter (`jda fmt`)
**Status:** [ ] TODO
**What:**
  - [ ] Canonical code formatting (indentation, spacing, line breaks)
  - [ ] `jda fmt` reformats in-place
  - [ ] `jda fmt --check` for CI (exit 1 if unformatted)
  - [ ] No configuration — one true style (like `gofmt`)
**Why:** Eliminates bikeshedding. CI-enforceable code quality.

---

### 24. LSP server (IDE support)
**Status:** [ ] PARTIAL (spec at `tools/lsp.jda`)
**What:**
  - [ ] Go-to-definition
  - [ ] Hover type info
  - [ ] Autocomplete
  - [ ] Error diagnostics (red squiggles)
  - [ ] Rename symbol
  - [ ] VS Code extension published on marketplace
  - [ ] Neovim/Emacs LSP compatibility
**Why:** Modern development requires IDE intelligence.

---

### 25. Debugger support
**Status:** [ ] TODO
**What:**
  - [ ] DWARF debug info emission in ELF binaries
  - [ ] Source-level debugging with GDB/LLDB
  - [ ] Breakpoints, step, inspect variables
  - [ ] Stack trace on crash (with source locations)
**Why:** Without debugging, development is painful. C has had this for 40 years.

---

### 26. REPL / interactive mode
**Status:** [ ] TODO
**What:**
  - [ ] `jda repl` launches interactive session
  - [ ] Evaluate expressions, define functions
  - [ ] Tab completion
  - [ ] History
**Why:** Python/Ruby developers expect this. Great for learning the language.

---

## Phase 5: Documentation

### 27. Language reference manual
**Status:** [ ] TODO
**What:**
  - [ ] Complete grammar specification
  - [ ] All types: primitives, structs, enums, arrays, pointers
  - [ ] All statements: let, if, loop, match, ret, fn, struct, enum, impl, trait
  - [ ] Operators and precedence rules (left-to-right evaluation)
  - [ ] Ownership and borrowing rules
  - [ ] Memory model
**Where:** `docs/reference/` or website
**Why:** Developers need a definitive reference. Rust has "The Book", Go has the spec.

---

### 28. Getting Started tutorial
**Status:** [ ] TODO
**What:**
  - [ ] Install Jda (one-liner for each OS)
  - [ ] Hello World
  - [ ] Variables and types
  - [ ] Functions
  - [ ] Structs
  - [ ] Control flow (if/else, loop, match)
  - [ ] Error handling
  - [ ] Building a small project (CLI tool or web server)
**Where:** `docs/tutorial/` or website
**Why:** First 30 minutes determine if someone adopts a language.

---

### 29. Standard library API documentation
**Status:** [ ] TODO
**What:**
  - [ ] Auto-generated from doc comments in source
  - [ ] Every public function: signature, description, example
  - [ ] Searchable HTML site (like docs.rs / pkg.go.dev)
  - [ ] `jda doc` command to generate locally
**Why:** Developers won't use what they can't look up.

---

### 30. Examples and cookbook
**Status:** [ ] PARTIAL (4 examples exist)
**What:** Expand `examples/` to cover real-world use cases:
  - [ ] CLI argument parser
  - [ ] File I/O (read CSV, write JSON)
  - [ ] HTTP server and client
  - [ ] WebSocket chat server
  - [ ] Database query (SQLite)
  - [ ] Concurrent worker pool
  - [ ] ML inference (load model, run prediction)
  - [ ] Game of Life (terminal graphics)
  - [ ] Markdown to HTML converter
  - [ ] Build tool / task runner
**Why:** Examples are the fastest way to learn. "Show me the code."

---

### 31. Website (jda-lang.org)
**Status:** [ ] TODO
**What:**
  - [ ] Landing page with elevator pitch
  - [ ] Install instructions (Linux/macOS/Windows)
  - [ ] Online playground (WASM-compiled Jda in browser)
  - [ ] Documentation hub (tutorial, reference, API docs)
  - [ ] Blog (release announcements, design decisions)
  - [ ] Package registry search
**Why:** Every serious language has a website. It's the front door.

---

## Phase 6: Performance and Production Readiness

### 32. Optimizing compiler backend
**Status:** [ ] TODO
**What:**
  - [ ] Register allocation (linear scan or graph coloring)
  - [ ] Instruction selection (better than 1:1 mapping)
  - [ ] Dead code elimination (already started)
  - [ ] Constant folding (already started)
  - [ ] Inlining
  - [ ] Loop unrolling
  - [ ] Tail call optimization
  - [ ] Benchmark suite comparing Jda to C/Go/Rust
**Why:** "Machine-code fast" is the promise. Must prove it with numbers.

---

### 33. Concurrency runtime (J-Threads)
**Status:** [ ] TODO (spec at `concurrency/`)
**What:**
  - [ ] Green thread scheduler (M:N threading)
  - [ ] Lock-free channel implementation
  - [ ] `spawn` keyword to launch J-Thread
  - [ ] Channel send/recv syntax
  - [ ] Work-stealing scheduler
**Why:** "Concurrent like Go" is the promise. goroutines are Go's killer feature.

---

### 34. ML runtime (tensors, autograd)
**Status:** [ ] TODO (spec at `stdlib/ml/`)
**What:**
  - [ ] Tensor type as language primitive
  - [ ] Shape checking at compile time
  - [ ] Autograd (reverse-mode automatic differentiation)
  - [ ] GPU backends (CUDA PTX, ROCm, Metal)
  - [ ] AVX-512 / NEON SIMD acceleration
  - [ ] Pre-trained model loading
**Why:** "ML-native" is the unique differentiator vs all competitors.

---

### 35. C FFI (Foreign Function Interface)
**Status:** [ ] TODO
**What:**
  - [ ] Call C functions from Jda
  - [ ] Expose Jda functions to C
  - [ ] C header file parser (basic)
  - [ ] libc interop layer (optional, for porting existing code)
**Why:** No language succeeds in isolation. Must interop with existing C ecosystem.

---

## Summary: What Competitors Have That Jda Doesn't (Yet)

| Feature | C | Go | Rust | Python | Jda |
|---------|---|-----|------|--------|-----|
| Cross-platform | ✅ | ✅ | ✅ | ✅ | ❌ Linux x86-64 only |
| Package manager | make/cmake | go mod | cargo | pip | ❌ Spec only |
| Test framework | external | go test | cargo test | pytest | ❌ None |
| Formatter | clang-format | gofmt | rustfmt | black | ❌ None |
| Debugger | GDB | dlv | rust-gdb | pdb | ❌ None |
| IDE support | clangd | gopls | rust-analyzer | pylsp | ❌ Spec only |
| REPL | ❌ | ❌ | ❌ | ✅ | ❌ None |
| Generics | templates | ✅ | ✅ | ✅ | ❌ None |
| Error handling | errno | error interface | Result<T,E> | exceptions | ❌ None |
| Concurrency | pthreads | goroutines | async/tokio | asyncio | ❌ Spec only |
| Documentation | man pages | go doc | rustdoc | docstrings | ❌ None |
| Website | cppreference | go.dev | rust-lang.org | python.org | ❌ None |
| Ecosystem size | massive | large | growing | massive | ❌ Zero |
| Self-hosting | ✅ | ✅ | ✅ (via LLVM) | N/A | 🔧 In progress |

---

## Priority Order

**Must-have (blocks everything):**
1. Loop mutation (#1) → Function calls (#2) → Structs (#3) → Arrays (#4) → Self-hosting (#8)

**Must-have (blocks adoption):**
2. Cross-platform installers (#9, #10, #11)
3. Getting Started tutorial (#28) + Language reference (#27)
4. Type checking (#13) + Error handling (#16)

**Should-have (competitive parity):**
3. Package manager (#21) + Test framework (#22) + Formatter (#23)
4. Enums (#15) + Generics (#17) + Traits (#19)
5. LSP + VS Code extension (#24)
6. Website (#31)

**Nice-to-have (differentiation):**
7. Concurrency runtime (#33) + ML runtime (#34)
8. Debugger (#25) + REPL (#26)
9. C FFI (#35) + WASM target (#12)
