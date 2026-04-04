# Phase 2 — Minimal Release Plan

**Goal**: Make Jda usable by external developers. One-command install, clear error messages, no dependency on jda0.

**Prerequisite**: Phase 1 (self-hosting) complete. jda1_sh3 == jda1_sh4, 1,769,979 bytes.

---

## Current State Assessment

| Area | Status | Gap |
|------|--------|-----|
| CLI | `jda1 <input> <output>` only, silent exit on bad args | No flags, no help, no `build`/`run` subcommands |
| Error reporting | `panic()` with hardcoded messages, no source locations | No line/col tracking, no context snippets |
| Stdlib | 6 files exist (`fmt`, `fs`, `json`, `crypto`, `time`, `process`) but **none integrated** into jda1 | jda1 can't import external files yet |
| Bootstrap | Still requires jda0 (NASM assembly) to build jda1 from scratch | Need to ship self-hosted binary as bootstrap |
| Tests | 63 stage0 + 13 stage1 conformance tests | No automated test runner, no CI |
| Install | Manual Docker build | No installer, no release binaries |

---

## Milestones (in dependency order)

### M1: Retire jda0 — Use Self-Hosted jda1 as Bootstrap

**Why first**: Everything else depends on a stable, trusted bootstrap binary. Once jda0 is retired, we only maintain Jda code.

**Tasks**:
1. Commit the self-hosted `jda1_stage3` binary (1.77 MB) as the official bootstrap compiler
   - Store at `bootstrap/bin/jda1-bootstrap` (checked into git via LFS or raw binary)
   - Add SHA-256 hash in `bootstrap/bin/CHECKSUMS`
2. Update Makefile to use `jda1-bootstrap` instead of building jda0 → jda1
   - New flow: `jda1-bootstrap` compiles `jda1.jda` → `jda1` (single step)
   - Keep jda0 source in `bootstrap/stage0/` for historical reference but remove it from the default build
3. Verify the new bootstrap: `jda1-bootstrap` → jda1_a → jda1_b, confirm jda1_a == jda1_b
4. Update Docker image to no longer require NASM (optional, reduces image size)
5. Document bootstrap update procedure: when jda1.jda changes, rebuild and re-commit the bootstrap binary

**Removes**: NASM dependency for new users. Build becomes: `jda1-bootstrap compiles jda1.jda` — done.

**Risk**: Binary in git repo. Mitigate with checksums + reproducible build instructions.

---

### M2: Line/Column Tracking in Lexer

**Why second**: Every downstream feature (error diagnostics, CLI error messages, future LSP) needs source locations.

**Current state**: The lexer in `jda1.jda` tokenizes into `Token` structs (32 bytes: type, string span, immediate). No line or column fields.

**Tasks**:
1. Add `line` and `col` fields to the `Token` struct
   - Increases Token from 32 → 48 bytes (add 2 i64 fields)
   - Update `sizeof_Token` constant and all struct offset references
   - Regenerate `jda0_constants.asm` and `jda0_structs.asm` (if jda0 is still in use at this point)
2. Track line/col during lexing
   - Add `g_line` and `g_col` counters in the lexer
   - Increment `g_line` on `\n`, reset `g_col`
   - Stamp each token with current line/col at emit time
3. Propagate locations through JIR
   - Add `src_line` field to `Instr` struct (96 → 104 bytes)
   - Copy token location when emitting JIR instructions
4. Self-host with the new Token/Instr sizes — verify convergence still holds

**Risk**: Struct size changes ripple through the entire compiler. Must update sizeof constants, regalloc spill offsets, and lowering code. Plan for 1-2 debugging cycles.

---

### M3: Error Diagnostics

**Why third**: Depends on M2 (source locations). This is the highest-impact user-facing feature.

**Current state**: `panic("message")` → stderr, exit 1. No context, no source location, no recovery.

**Tasks**:
1. Create `report_error(token: &Token, msg: &i8)` function in jda1.jda
   - Prints: `error: <msg>` line
   - Prints: `  --> <filename>:<line>:<col>` location line
   - Prints: source line with `^` caret pointing to the error column
   - Exits with code 1
2. Replace all `panic()` calls with `report_error()` where a token is available (~15-20 call sites)
   - Parser errors: unexpected token, missing semicolon, unclosed brace
   - Type errors: struct field not found, wrong argument count
   - Codegen errors: undefined variable, undefined function
3. Add warning support (non-fatal): `report_warning(token: &Token, msg: &i8)`
   - Unused variables, unreachable code (future use)
4. Source line retrieval: keep the source buffer around after lexing, add a function to extract line N from the buffer

**Target output**:
```
error: undefined variable 'foo'
  --> src/main.jda:12:5
   |
12 |     let y = foo + 1
   |             ^^^
```

**Risk**: Keeping the full source buffer in memory for error context. At 512 KB max file size this is fine. No risk.

---

### M4: CLI Interface

**Why fourth**: Depends on M3 (error messages for bad CLI usage). Makes jda feel like a real tool.

**Current state**: `jda1 input.jda output` — no flags, no help, silent failure.

**Tasks**:
1. Implement argument parsing in `main()`
   - Parse `--help` / `-h` → print usage and exit 0
   - Parse `--version` / `-V` → print version and exit 0
   - Parse `-o <output>` → set output path (default: input stem, no extension)
   - Parse `--emit-asm` → dump x86-64 assembly to stdout (future, stub for now)
2. Implement subcommands:
   - `jda build <file.jda>` → compile to ELF binary (default subcommand)
   - `jda run <file.jda>` → compile to temp file, execute, delete temp
   - `jda version` → print version string
3. Add version string: `const VERSION = "0.1.0-dev"`
4. Proper error messages for bad usage:
   ```
   error: missing input file
   usage: jda build <file.jda> [-o output]
   ```
5. Exit codes: 0 = success, 1 = compile error, 2 = CLI usage error

**Scope decision**: The "binary" is still called `jda1` internally. The user-facing name is `jda`. We can rename the output binary or create a wrapper later. For now, `jda1 build foo.jda` works.

---

### M5: Minimal Standard Library Integration

**Why fifth**: Depends on M4 (CLI), and the compiler needs multi-file support or inlining.

**Current state**: `stdlib/` has 6 files (fmt, fs, json, crypto, time, process) with ~3,400 lines total. But jda1 compiles a **single file** — no imports, no includes.

**Two approaches** (decide before implementing):

#### Option A: Source Concatenation (simpler, do this first)
- `jda build --stdlib foo.jda` → prepend `stdlib/fs.jda` + `stdlib/fmt.jda` + `stdlib/time.jda` to source before compilation
- No language changes needed
- User code can call stdlib functions directly
- Downsides: namespace pollution, slower compile (larger source), no selective imports

#### Option B: `import` Statement (proper, Phase 3)
- `import fs` → lexer/parser resolves to `stdlib/fs.jda`, compiles separately, links symbols
- Requires: module system, symbol resolution across compilation units, linker changes
- This is Phase 3 scope — too complex for minimal release

**Tasks (Option A)**:
1. Add `--stdlib` flag to CLI (or make it default)
2. At compile time, read and concatenate: `stdlib/fs.jda` + `stdlib/fmt.jda` + `stdlib/time.jda` + user source
3. Validate that stdlib functions compile correctly with jda1
   - The existing stdlib files use language features (enums, Result, `?` operator) that jda1 doesn't support yet
   - **Rewrite stdlib files** to use only current jda1 features: functions, structs, arrays, pointers, syscalls
4. Create minimal versions:
   - `fs_read(path: &i8, buf: &i8, max: i64) -> i64` — open, read, close, return bytes read
   - `fs_write(path: &i8, data: &i8, len: i64) -> i64` — open, write, close
   - `fmt_i64(buf: &i8, val: i64) -> i64` — integer to string, return length
   - `time_now() -> i64` — clock_gettime syscall, return nanoseconds

**Risk**: The existing stdlib files are aspirational — they use language features that don't exist yet (enums, Result, `?`). Must rewrite to current feature set.

---

### M6: Test Runner & CI

**Tasks**:
1. Create `tools/run_tests.sh` (or `tools/run_tests.py`)
   - For each `.jda` file in `tests/conformance/stage1/pass/`:
     - Compile with jda1
     - Run the binary
     - Compare stdout to `.expected` file
     - Compare exit code to `.exit` file (if present, default 0)
   - Report: PASS/FAIL count, list failures
2. Expand stage1 test suite from 13 → 50+ tests:
   - Arithmetic, comparisons, if/else, loops, functions, structs, arrays, pointers, string literals, print, syscalls
   - Edge cases: empty main, nested structs, large arrays, recursion
3. Add self-host convergence test:
   - Build jda1_a and jda1_b, verify byte-identical
4. GitHub Actions CI (`.github/workflows/ci.yml`):
   - Build Docker image
   - Run conformance tests
   - Run self-host convergence check
   - Run on push to main and PRs

---

### M7: Linux Installer & Release

**Tasks**:
1. Create `install.sh`:
   ```bash
   curl -fsSL https://jda-lang.org/install.sh | sh
   ```
   - Downloads pre-built `jda` binary for Linux x86-64
   - Places in `~/.jda/bin/jda`
   - Adds to PATH (appends to `.bashrc`/`.zshrc`)
   - Verifies SHA-256 checksum
2. Create GitHub Release workflow:
   - Tag `v0.1.0`
   - Build jda1 in Docker, self-host verify, package as `jda-0.1.0-linux-x86_64.tar.gz`
   - Upload to GitHub Releases
3. Add `VERSION` file at project root
4. Write `docs/getting-started.md`:
   - Install → write hello.jda → `jda build hello.jda` → `./hello` → done

---

## Execution Order & Dependencies

```
M1 (retire jda0) ──────────────────────────────────────┐
                                                         │
M2 (line/col tracking) ─── M3 (error diagnostics) ───── M4 (CLI) ─── M5 (stdlib)
                                                         │
                                                    M6 (tests/CI) ─── M7 (release)
```

**Critical path**: M1 → M2 → M3 → M4 → M7

M5 (stdlib) and M6 (tests) can be parallelized alongside the critical path once M4 is done.

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Token struct resize breaks self-hosting | High — could take days to debug | Do M1 first so we bootstrap from self-hosted binary, not jda0. Test convergence after every struct change. |
| Existing stdlib uses unsupported features | Medium — rewrite needed | Write minimal stdlib from scratch using only current features. Don't try to salvage existing files. |
| Binary-in-git bloat | Low — 1.77 MB once | Use Git LFS if it grows. Single binary is fine. |
| CI needs Docker (slow) | Low — acceptable for now | Cache Docker image layer. Full pipeline takes ~30s. |
| No import system limits stdlib usefulness | Medium — concatenation is hacky | Accept it for 0.1. Proper imports are Phase 3. |

---

## Definition of Done

Phase 2 is complete when an external developer can:

```bash
# Install
curl -fsSL https://jda-lang.org/install.sh | sh

# Write code
cat > hello.jda << 'EOF'
fn main() -> i64 {
    print("Hello, world!\n")
    ret 0
}
EOF

# Build and run
jda build hello.jda
./hello
# Output: Hello, world!

# Get useful errors
cat > bad.jda << 'EOF'
fn main() -> i64 {
    let x = foo + 1
    ret 0
}
EOF

jda build bad.jda
# error: undefined variable 'foo'
#   --> bad.jda:2:13
#    |
#  2 |     let x = foo + 1
#    |             ^^^
```

No NASM, no Docker, no jda0. Just `jda build` and go.
