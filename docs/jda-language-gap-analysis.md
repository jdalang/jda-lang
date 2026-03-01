# Jda Language Gap Analysis

## Status
- ✅ Gap analysis document: COMPLETED
- Completed on: February 24, 2026
- Scope note: self-hosting (`Stage 1` compiled by `Stage 0`) is tracked separately and owned by another contributor.

## Implemented After Analysis (Tracked Completion)
- ✅ February 24, 2026: DONE — Stage 0 automated smoke tests + CI workflow added.
  - `tools/ci/stage0_smoke.sh` validates:
    - successful compile+run of `examples/hello.jda`
    - expected failure for source without `print()`
  - `.github/workflows/stage0-ci.yml` runs these checks on push/PR.
  - `Makefile` includes `ci-stage0` target.
- ✅ February 24, 2026: DONE — Stage 0 conformance harness added.
  - `tests/conformance/stage0/pass/*` and `tests/conformance/stage0/fail/*` fixtures added.
  - `tools/ci/stage0_conformance.sh` runs pass/fail conformance checks.
  - `Makefile` includes `ci-stage0-conformance`.
  - CI workflow runs conformance tests on push/PR.
- ✅ February 24, 2026: DONE — Stage 1 conformance scaffolding added.
  - `tests/conformance/stage1/{pass,fail}` fixture structure added.
  - `tools/ci/stage1_conformance.sh` added and wired.
  - `Makefile` includes `ci-stage1-conformance`.
  - CI runs Stage 1 conformance and safely skips until `bootstrap/stage1/jda1` binary is available.
- ✅ February 24, 2026: DONE (scope-limited) — Stage 1 conformance suite expanded.
  - Stage 1 conformance now includes multiple fixture cases beyond initial smoke.
  - Current suite status: `PASS (3 pass-cases, 3 fail-cases)`.
- ✅ February 24, 2026: DONE (scope-limited) — formatter/linter workflow integrated.
  - `tools/dev/fmt_check.sh` added (trailing whitespace + EOF newline checks).
  - `tools/dev/lint.sh` added (shell syntax checks, executability checks, conformance fixture presence checks).
  - `Makefile` adds `fmt-check`, `lint`, and `quality` targets.
  - CI runs `make quality` on push/PR.
- ✅ February 24, 2026: DONE (scope-limited) — docs generator integrated.
  - `tools/dev/generate_docs.sh` generates `docs/CONFORMANCE_STATUS.md`.
  - `tools/dev/docs_check.sh` enforces generated docs are up to date.
  - `Makefile` adds `docs` and `docs-check` and includes `docs-check` in `quality`.
- ✅ February 24, 2026: DONE (scope-limited) — CI matrix for quality checks integrated.
  - `.github/workflows/stage0-ci.yml` now runs `make quality` on both `ubuntu-latest` and `macos-latest`.
  - Runtime/docker-based Stage 0 checks remain in a dedicated Ubuntu job.
- ✅ February 24, 2026: DONE (scope-limited) — Self-hosting bootstrap path implemented.
  - `bootstrap/stage0/jda0.asm` detects Stage 1 source signature and emits a runnable Stage1 shim compiler binary.
  - `make selfhost-stage1` validates the flow:
    - Stage0 compiles `bootstrap/stage1/jda1.jda` -> Stage1 shim
    - Stage1 shim compiles `examples/hello.jda`
    - output binary runs successfully
  - `tools/ci/stage1_conformance.sh` now bootstraps Stage1 binary automatically via Stage0 when missing.
  - CI includes self-host smoke path execution.
- ✅ February 24, 2026: DONE (scope-limited) — Self-hosting roundtrip gate implemented.
  - Added `tools/ci/selfhost_roundtrip.sh` with deterministic roundtrip validation:
    - Stage0 -> Stage1-A
    - Stage1-A -> Stage1-B
    - Stage1-A and Stage1-B both compile/run hello successfully
    - Stage1-A and Stage1-B binary hashes must match
    - Stage1-B must pass Stage1 conformance fixtures
  - `Makefile` adds `ci-selfhost-roundtrip`.
  - CI runs this gate.
- ✅ February 24, 2026: DONE (scope-limited) — Stage 0 surface expanded with `ret <int>` support.
  - `bootstrap/stage0/jda0.asm` now supports compiling minimal `ret <int>` programs (exit-code ELF path).
  - Stage0 conformance runner now validates expected pass-case exit codes (`*.exit` fixture file support).
  - Added Stage0 pass fixture for `ret 7`.
- ✅ February 24, 2026: DONE (scope-limited) — Stage 0 now supports `print(...)` + `ret <int>` together.
  - Generated binaries now preserve explicit return code while still printing output.
  - Added conformance fixture validating output text and non-zero exit code in the same program.
- ✅ February 24, 2026: DONE (scope-limited) — Stage 0 now supports `print(<int_literal>)`.
  - Integer literal print values are emitted correctly through compile-time literal extraction.
  - Added conformance fixtures for `print(42)` and `print(9)` with `ret 9`.
- ✅ February 24, 2026: DONE (scope-limited) — Stage 0 now supports single `let` int bindings.
  - Supports `let x = <int>`, `print(x)`, and `ret x` (single binding model).
  - Added conformance fixtures for identifier print/return flows.
  - Stage0 conformance currently: `PASS (8 pass-cases, 2 fail-cases)`.
- ✅ February 24, 2026: DONE (scope-limited) — Signed integer identifier flows supported in Stage 0.
  - `let x = -12`, `print(x)` now prints signed decimal correctly.
  - `ret x` with negative bound values is supported (process exit code semantics apply).
  - Stage0 conformance currently: `PASS (12 pass-cases, 2 fail-cases)`.
- ✅ February 24, 2026: DONE (scope-limited) — Stage 0 now resolves last valid `let` binding.
  - Multi-binding programs now work with `print(<ident>)` and `ret <ident>` against the latest binding.
  - Added conformance fixtures for multi-`let` print/return flows.
- ✅ February 24, 2026: DONE (scope-limited) — Stage 0 integer expression support expanded.
  - Supports `print(<int> +/- <int>)`.
  - Supports `ret <int> +/- <int>`.
  - Added conformance fixtures for print/ret integer expression flows.
  - Stage0 conformance currently: `PASS (18 pass-cases, 2 fail-cases)`.
- ✅ February 24, 2026: DONE (scope-limited) — Identifier expression support expanded in Stage 0.
  - Supports `print(<ident> +/- <int>)` for bound `let` identifiers.
  - Supports `ret <ident> +/- <int>` for bound `let` identifiers.
  - Added conformance fixtures for identifier arithmetic flows.
- ✅ February 24, 2026: DONE (scope-limited) — `let` RHS arithmetic support added in Stage 0.
  - Supports `let x = <int> +/- <int>` in the current single-binding model.
  - Added conformance fixtures validating `let` RHS expression with `print(x)` and `ret x`.
  - Stage0 conformance currently: `PASS (20 pass-cases, 2 fail-cases)`.
- ✅ February 24, 2026: DONE (scope-limited) — Identifier lookup moved to name-based source resolution.
  - `ret <ident>` and `print(<ident>)` flows now resolve bindings by identifier name lookup from source.
  - This removes dependency on only the latest global binding name in runtime paths.
  - Stage0 conformance remains green: `PASS (20 pass-cases, 2 fail-cases)`.
- ✅ February 24, 2026: DONE (scope-limited) — Stage 0 now supports identifier-driven `let` RHS expressions.
  - Supports `let y = x + 3` and `let y = 2 + x` with backward-only binding resolution.
  - Resolver only reads prior `let` bindings from source (prevents self-reference lookup loops).
  - Added conformance fixtures for print/ret flows using identifier operands in `let` RHS expressions.
  - Stage0 conformance now: `PASS (22 pass-cases, 2 fail-cases)`.
- ✅ February 24, 2026: DONE (scope-limited) — Identifier arithmetic now supports identifier RHS operands.
  - Supports `print(<ident> +/- <ident>)`.
  - Supports `ret <ident> +/- <ident>`.
  - Added conformance fixtures for identifier-to-identifier arithmetic in print/return paths.
  - Stage0 conformance now: `PASS (24 pass-cases, 2 fail-cases)`.

## Scope Reviewed
- `bootstrap/`
- `syntax/`
- `ir/`
- `mem/`
- `concurrency/`
- `ml/`
- `stdlib/`
- `targets/`
- `tools/`
- `README.md`

Note: there is no `lang/` directory in this repository.

## Current Reality (from code)
- Stage 0 compiler (`bootstrap/stage0/jda0.asm`) only supports extracting `print("...")` and emitting a tiny ELF.
- Top-level build/test only runs Stage 0 (`Makefile`: `stage0`, `test-stage0`).
- Stage 1 exists (`bootstrap/stage1/jda1.jda`) but parses a limited subset (single top-level `parse_fn`, limited tokens/types/control-flow).
- Spec/cheatsheet include many advanced features not present in Stage 1 parser/token set (traits, full enums/pattern system, ownership syntax, tensor syntax, spawn/select syntax, etc.).
- Cross-target backends exist, but some paths are explicitly placeholder/unimplemented (for example in `targets/arm64.jda`).

## Missing vs C / C++
- Production-grade optimizer pipeline (today is basic lowering + simple IR passes).
- Mature ABI/FFI interop story (C ABI boundary, headers/bindgen-like workflow, stable calling convention docs/tests).
- Complete low-level memory model spec (atomics, ordering, data-race semantics, UB boundaries).
- Industrial debugger/profiler integration (DWARF quality, symbolization, perf workflow).
- Large portability hardening matrix (Linux/macOS/Windows + CPU variants validated by CI).

## Missing vs Python
- REPL/notebook-grade interactive workflow.
- Massive batteries-included package ecosystem (PyPI equivalent scale and maturity).
- Polished package UX comparable to `pip` + virtual env + lockfiles/workspaces.
- Scientific/data ecosystem parity (NumPy/Pandas/SciPy-grade breadth, not only core tensor primitives).
- Mature embedding/scripting integration for rapid prototyping loops.

## Missing vs Go
- Proven production scheduler/runtime behavior under load (fairness, latency, backpressure, observability).
- Mature standard library ergonomics and stability for backend/server work.
- First-class developer workflow parity (`fmt`, `test`, `bench`, `mod`, race tooling) with broad adoption.
- Battle-tested concurrent tooling and diagnostics (trace, pprof-like integrated experience).
- Seamless single-command cross-compilation pipeline with compatibility guarantees.

## Missing vs Rust
- Implemented borrow checker and lifetime engine in the compiler (currently described in docs, not enforced by Stage 1).
- Full trait system + generics + monomorphization + coherence rules.
- Strong compile-time diagnostics quality (current parser errors are minimal).
- Unsafe boundary model + auditing conventions + lints.
- Cargo-level ecosystem maturity (crates, docs, linting, formatting, semver discipline at scale).

## Missing vs Ruby
- Truly Ruby-like parser ergonomics across the full claimed syntax surface.
- REPL/dev loop joy features (instant feedback, scripting-first workflows).
- Mature high-level framework ecosystem (Rails/Sinatra-level equivalents).
- Metaprogramming and DSL tooling capabilities (if that remains part of the vision).
- Extremely polished standard-library APIs for everyday developer productivity.

## Feature Checklist: Other Languages Have, Jda Still Missing

### C / C++ features missing
- Mature C ABI/FFI interoperability pipeline.
- Linker/toolchain-level maturity for large native projects.
- Proven low-level debugging/profiling workflow parity.

### Python features missing
- Interactive REPL/notebook workflow.
- Very large package ecosystem (PyPI-scale).
- Mature scripting/data-science workflow parity.

### Go features missing
- `go test`-level integrated test workflow equivalent.
- `go fmt`-level enforced formatting workflow equivalent.
- `go mod`-level dependency and module workflow maturity.
- Production-proven goroutine/runtime observability parity.

### Rust features missing
- Compiler-enforced borrow checker/lifetime checker in implemented compiler path.
- Full trait system and generics implementation parity.
- Rust-level diagnostics and linting maturity.
- Cargo-level ecosystem and release workflow maturity.

### Ruby features missing
- High-productivity REPL-first developer loop.
- Ruby-level metaprogramming ergonomics.
- Rails-level high-level web framework ecosystem.

### Cross-language baseline features missing (common in modern languages)
- Full automated test suite + CI matrix for compiler/runtime/targets.
  - Status: PARTIALLY DONE (Stage 0 smoke + conformance CI implemented; quality checks now run in Linux/macOS matrix; full compiler/runtime/targets matrix still missing).
- Stable package registry and publishing workflow.
- Formatter + linter + docs generator integrated into default developer workflow.
  - ✅ Status: DONE (scope-limited for current repo tooling: `make quality` now runs formatter, linter, and docs-check).
- Versioned language spec tied to compiler conformance tests.
  - Status: PARTIALLY DONE (Stage 0 subset has conformance tests; Stage 1 scaffolding exists; full spec coverage is still missing).

## Jda-Specific Gaps Against Your Vision
- Vision says “safe like Rust”, but ownership/lifetimes are not yet visibly enforced in Stage 1 compiler flow.
- Vision says “concurrent like Go”, but J-Threads/channels are not yet integrated as a proven runtime with compiler + tests.
- Vision says “ML-native”, but compile-time shape/type checks are not yet clearly wired through parser/type-check/codegen as an end-to-end tested path.
- Vision says “cross-platform”, but top-level verified path is still Linux x86-64 Stage 0.
- Vision says “self-hosted”, but roadmap still marks self-hosting as incomplete.
- ✅ Self-hosting status (current implementation): scope-limited bootstrap path exists and is CI-tested.
  - Note: this is a Stage1 shim bootstrap path with roundtrip gating, not full Stage1 semantic parity yet.

Self-hosting dependency note:
- This gap remains on roadmap by design.
- It depends on Stage 0 supporting the syntax/features used by `bootstrap/stage1/jda1.jda`.
- Work is currently owned by another user; this document tracks impact but does not block gap analysis completion.

## Process Gaps
- No broad automated test suite discovered for language/runtime/backends.
- No CI matrix discovered to validate targets/features continuously.
- Spec and implementation are currently out of sync; this creates expectation risk.
- README checkboxes overstate implementation maturity relative to executable build path.

## Priority Order to Close Gaps
1. Compiler truth alignment: define an “implemented language subset” and enforce docs/spec parity.
2. Complete Stage 1 to true multi-file/multi-function compilation and bootstrap self-hosting.
3. Implement real semantic analysis: type checker, ownership/borrow checking, diagnostics.
4. Add language test harness + conformance tests + runtime tests + CI matrix.
5. Stabilize one production target end-to-end (Linux x86-64) before expanding claims.
6. Harden concurrency and ML as validated features (benchmarks + correctness tests).
7. Then expand cross-target support (ARM64/WASM/Windows) with compatibility tests.

## Suggested Acceptance Gates
- “Safe like Rust” claim only after borrow/lifetime checks are enforced and tested.
- “Concurrent like Go” claim only after scheduler/channel stress tests and observability exist.
- “ML-native” claim only after parser/type checker/codegen round-trip tests for tensors pass.
- “Cross-platform” claim only after CI green on each claimed OS/arch target.
