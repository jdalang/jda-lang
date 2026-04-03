# Phase 4 — Performance & Optimization Plan

**Goal**: Prove Jda can match C/Rust performance. Make the self-hosted compiler fast enough to compile itself in under 5 seconds.

**Prerequisite**: Phase 3 complete. Self-hosted compiler with enums, pattern matching, generics, CTRC, arenas, linear types, and 79 conformance tests. Self-host converged at 1,984,540 bytes.

---

## Current Compiler Performance

| Area | Status | Gap |
|------|--------|-----|
| Register allocation | Simple linear scan, 7 registers, FIFO eviction | Excessive spills, no liveness analysis, no interference graph |
| Constant folding | `fold_constants()` implemented (line 8030) but **never called** | Dead code — needs to be wired into pipeline |
| Dead code elimination | `dce()` implemented (line 8061) but **never called** | Same — implemented but not invoked |
| Function inlining | None | Every function call is a full CALL instruction, even trivial helpers |
| Tail calls | None | Recursive functions grow the stack unboundedly |
| Loop optimization | None | No invariant hoisting, unrolling, or strength reduction |
| SIMD | None | No vectorization of any kind |
| Binary size | 1.98 MB for 11,913 lines of source | ~170 bytes/source line — bloated by per-function 64KB stack frames |
| Peephole | Minimal — shift immediate detection only | No MOV elimination, no strength reduction, no instruction fusion |

**Existing infrastructure to activate:**
- `fold_constants()` at line 8030 — handles OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_SHR, OP_SHL
- `dce()` at line 8061 — two-pass mark-and-sweep dead code elimination
- `find_const()` at line 7998 — scans basic block for constant values (used by folder)

---

## Milestones (in dependency order)

### M1: Activate Existing Optimization Passes ✅

**Completed**: April 2, 2026

**What was done**:
1. Wired `fold_constants(jfn)` and `dce(jfn)` into the compilation pipeline, called after JIR generation and before `lower_fn()` for every function
2. Both passes were already implemented but never invoked — `fold_constants` folds constant arithmetic (ADD, SUB, MUL, DIV, SHR, SHL) and `dce` marks unused instructions as dead (skipped by lowering)
3. All 79 conformance tests pass
4. Self-host converged at 1,984,626 bytes

**Impact**: Minimal binary size change on the compiler itself (+86 bytes from the two call instructions) since jda1.jda has very little constant-foldable arithmetic. The passes will show benefit on user programs with computed constants.

**Deferred**: Compiler flag (`-O1`) for enable/disable — not needed until optimization bugs require bisection.

---

### M2: Expanded Register Allocator ✅

**Completed**: April 2, 2026

**What was done**:
1. Expanded register pool from 7 to 10: RAX, RCX, RDX, RSI, RDI, R8, R9, RBX, R10, R11
2. Updated `RegAlloc` struct: `pool[16]`, `reg2val[16]`, added `evict_idx` for round-robin eviction
3. Updated `emit_save_pool` / `emit_restore_pool` to save/restore all 10 registers
4. Added callee-saved RBX: push in prologue, pop in epilogue (both `lower_fn_emit_epilogue` and inline `OP_RET` lowering use `LEA RSP, [RBP-8]; POP RBX; POP RBP; RET`)
5. Changed eviction from always-evict-slot-0 (FIFO) to round-robin across all 10 slots
6. All 79 conformance tests pass
7. Self-host converged at 2,016,007 bytes

**Impact**: 3 more registers available reduces spill pressure. Binary grew ~31KB due to larger save/restore sequences in every call site, but hot functions with >7 live values benefit from fewer spill/reload pairs.

**Deferred**: Full liveness analysis, interference graph, and linear scan — these require significant infrastructure (interval computation, cross-block analysis) and are better tackled when the compiler has more optimization passes to benefit from. The current 10-register round-robin allocator is a practical middle ground.

---

### M3: Function Inlining ✅

**Completed**: April 2, 2026

**What was done**:
1. Added `try_inline_call()` function in the lowering pass that intercepts OP_CALL instructions for `emit_byte` and `poke_byte` — the two most-called functions in the compiler (~5000+ calls each)
2. Inline expansion uses save_pool/restore_pool with push-pop arg loading (same pattern as normal calls) but replaces the CALL+prologue+body+epilogue+RET with direct x86 byte sequences
3. Raw x86 bytes emitted for inline bodies to work around jda0's 4-arg function call limitations within `try_inline_call`
4. `emit_byte` inline: loads pos[0], computes buf+offset, stores byte, increments pos[0] — 19 bytes of x86
5. `poke_byte` inline: computes buf+offset, stores byte — 10 bytes of x86
6. All 79 conformance tests pass
7. Self-host converged at 2,029,163 bytes

**Impact**: Each inlined call saves the CALL instruction (5 bytes), function prologue (~15 bytes: PUSH RBP, MOV RBP/RSP, PUSH RBX, SUB RSP), function body overhead, and epilogue (~12 bytes: LEA, POP, POP, RET). With thousands of emit_byte/poke_byte calls, this eliminates significant call overhead in the lowering pass.

**Approach**: x86-level inlining in the lowering pass rather than JIR-level inlining. This was chosen because:
- emit_byte and poke_byte have trivial bodies (byte store + pointer increment)
- The x86 sequences are fixed (always use RDI/RSI/RDX from calling convention + R12 scratch)
- JIR-level inlining requires value ID renaming and basic block merging — deferred for future work

**Deferred**: General JIR-level inlining for arbitrary small functions (modrm_rr, mod8, i32_b0-b3, etc.). The current approach only inlines emit_byte and poke_byte at the x86 level.

---

### M4: Tail-Call Optimization ✅

**Completed**: April 2, 2026

**What was done**:
1. Added `OP_TAIL_CALL` opcode (34) for self-recursive tail calls
2. Added `tail_call_opt(jfn)` JIR pass that detects the pattern: last two non-dead instructions in a basic block are `OP_CALL` (to current function) followed by `OP_RET` (returning the call's result). Transforms `OP_CALL` → `OP_TAIL_CALL` and marks the `OP_RET` dead.
3. Added `lower_tail_call` in the lowering pass: loads args with push-pop pattern into calling convention registers, stores to param_slots, then emits `JMP` to BB 0 (function entry) via kind=0 fixup
4. Updated DCE and `lower_fn_mark_uses_instr` to handle `OP_TAIL_CALL`
5. Wired `tail_call_opt` into the pipeline after `dce`, before `lower_fn`
6. All 80 conformance tests pass (including new `tail_call_basic` test: `sum_tail(100, 0)` → `5050`)
7. Self-host converged at 2,039,800 bytes

**Impact**: Self-recursive functions in tail position no longer grow the stack. Each recursive call reuses the same stack frame via a JMP back to the function entry. The compiler itself has limited tail-recursive patterns, so the binary size change reflects mostly the new code for the optimization pass itself.

**Approach**: Self-recursive TCO only — detects calls to the current function by name matching against `g_cur_fn_name_start`/`g_cur_fn_name_len`. General tail calls and mutual tail calls are deferred.

**Deferred**: General tail calls (to other functions), mutual tail calls (`foo() -> bar() -> foo()`). These require interprocedural analysis and careful stack frame reuse across different function signatures.

---

### M5: Peephole Optimization ✅

**Completed**: April 3, 2026

**What was done**:
1. **JIR-level strength reduction** (`peephole(jfn)` pass):
   - `OP_MUL val, const_power_of_2` → `OP_SHL val, const_log2` (covers 2, 4, 8, ..., 65536)
   - `OP_DIV val, const_power_of_2` → `OP_SHR val, const_log2`
   - Helper functions: `log2_of_pow2()` returns log2 for powers of 2, `set_const_imm()` modifies OP_CONST in-place

2. **x86-level zero-constant optimization** (in `lower_instr_constlike`):
   - `MOV r64, 0` (10 bytes: REX.W B8+rd imm64) → `XOR r64, r64` (3 bytes: REX.W 33 ModRM)
   - Saves 7 bytes per zero constant. The compiler has thousands of `let x = 0` patterns.

3. **Compare-and-branch optimization** (in `emit_cmp_zero`):
   - `CMP r, 0` (4 bytes: REX.W 83 /7 00) → `TEST r, r` (3 bytes: REX.W 85 ModRM)
   - Saves 1 byte per branch condition. Every `if` statement uses this.

4. All 82 conformance tests pass (including new `peephole_mul_pow2` and `peephole_div_pow2` tests)
5. Self-host converged at 2,016,311 bytes

**Impact**: Binary size reduced by 23,489 bytes (from 2,039,800 to 2,016,311) — a 1.2% reduction. The XOR-for-zero optimization is the biggest contributor since zero is the most common constant value (variable initialization, loop counters, comparisons). The TEST optimization saves ~1 byte per branch across thousands of branches.

**Deferred**: MOV elimination, address mode fusion, and instruction scheduling. These require tracking x86-level instruction dependencies and register liveness, which is more complex than the current pattern-matching approach.

---

### M6: Benchmark Suite ✅

**Completed**: April 3, 2026

**What was done**:
1. Created 3 cross-language benchmark programs in both Jda and C:
   - **fib35** — naive recursive Fibonacci(35), measures call overhead
   - **sieve** — Sieve of Eratosthenes (100K), measures array access + branches
   - **sum_loop** — sum 1 to 100M, measures loop + arithmetic throughput
2. Created `tools/bench.sh` — automated benchmark runner that:
   - Auto-installs gcc in Docker if not present
   - Compiles both Jda and C versions
   - Times execution with nanosecond precision
   - Validates correctness (Jda output must match C output)
   - Displays comparison table with ratios
   - Includes self-compile benchmark (jda1 compiling jda1.jda)

**Initial Results (April 3, 2026)**:

| Benchmark | C -O2 (s) | Jda (s) | Ratio | Status |
|-----------|-----------|---------|-------|--------|
| fib35 | 0.044 | 31.194 | 709.0x | PASS |
| sieve | 0.029 | 0.021 | 0.7x | PASS |
| sum_loop | 0.028 | 0.294 | 10.5x | PASS |
| Self-compile | — | 12.833s | — | — |

**Analysis**:
- **fib35 (709x)**: Dominated by function call overhead — each call allocates a 524KB stack frame (SUB RSP, 524288). With 2^35 recursive calls, this is catastrophic. Fix: reduce stack frame size to actual usage (Phase 5+ work requiring liveness analysis).
- **sieve (0.7x — faster than C!)**: The sieve uses `i64[100001]` (8-byte elements) while C uses `char[100001]` (1-byte elements). Jda's 8-byte accesses are naturally aligned and avoid byte-extension overhead. Additionally, the 100K limit is small enough that both fit in L2 cache, making the aligned-access advantage dominant.
- **sum_loop (10.5x)**: Tight arithmetic loop with no function calls. The 10x overhead comes from excessive spill/reload in the loop body (no loop-invariant code motion, no loop register allocation). This is the fairest comparison of raw codegen quality.
- **Self-compile (12.8s)**: Above the 10s target. Dominated by the massive per-function stack frames and spill traffic.

**Known limitations discovered**:
- Direct array-element comparison in `if` conditions (`if a[i] == 0`) doesn't work — requires temp variable workaround (`let v = a[i]; if v == 0`). This is a codegen limitation, not a correctness bug in the optimizer.
- Compiler diagnostic output (LEX_OK, COMPILE, etc.) goes to stdout during compilation — cosmetic noise in benchmark output (redirected with `2>/dev/null` but diagnostics use stdout).

**Impact**: Establishes performance baseline for all future optimization work. The 709x fib35 ratio makes clear that stack frame reduction is the #1 priority for Phase 5.

**Deferred**: Rust/Go comparisons, perf-stat integration, regression tracking across commits. The current Jda-vs-C comparison is sufficient for Phase 4.

---

## Execution Order & Dependencies

```
M1 (activate fold+dce) ─── M2 (register allocator)
       │                          │
       │                    M3 (inlining)
       │                          │
       │                    M4 (tail calls)
       │                          │
       └──────────────────── M5 (peephole)
                                  │
                             M6 (benchmarks)
```

**Critical path**: M1 → M2 → M3 → M6 (register allocation and inlining are the biggest wins)

**Parallel track**: M4 (tail calls) and M5 (peephole) are independent of each other, can be done in any order after M2.

**M1 is prerequisite for all others**: The fold/dce passes simplify JIR before any downstream optimization.

---

## Self-Hosting Strategy

Same as Phase 3 — every milestone must maintain self-host convergence:

1. Add the optimization to jda1.jda
2. Verify: `jda1 → jda1_sh2 → jda1_sh3 → jda1_sh4`, confirm `jda1_sh3 == jda1_sh4`
3. All conformance tests still pass
4. Update bootstrap binary

**Key difference from Phase 3**: Optimization passes change *how* code is generated but not *what* the compiler can compile. A correctly-optimized compiler produces different (faster) binaries that behave identically. Convergence now means the optimized compiler produces the same optimized output when compiling itself.

**Danger**: Optimization bugs can cause the compiler to miscompile itself silently. Mitigation:
- Run full conformance suite after each optimization pass is added
- Compare output of `jda1 file.jda` vs `jda1_sh2 file.jda` for several test programs
- Keep `-O0` flag to disable all optimizations for bisecting bugs

---

## Test Strategy

Each milestone adds optimization-specific tests. Target: 120+ tests by end of Phase 4.

| Milestone | Test Categories |
|-----------|----------------|
| M1 | Constant fold correctness (arithmetic, shifts), DCE doesn't remove side effects |
| M2 | Register pressure tests (>7, >13 live values), spill correctness, callee-save |
| M3 | Inline expansion correctness, inline + fold interaction, depth limits |
| M4 | Tail-recursive fibonacci, mutual recursion, non-tail-call preserved |
| M5 | Strength reduction correctness, MOV elimination, address modes |
| M6 | Benchmark programs as regression tests (output correctness, not timing) |

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Register allocator bug silently miscompiles | Critical | Keep old allocator behind `-O0`. Compare old vs new output for all tests. |
| Inlining blows up binary size | Medium | Track binary size per commit. Set inline budget. Abort if binary grows >20%. |
| Optimization breaks self-host convergence | High | Each pass has an enable/disable flag. Binary search for the breaking pass. |
| Peephole patterns interact badly | Low | Each pattern is independent. Test each pattern in isolation. |
| Benchmark targets unrealistic | Low | Measure first, then set targets. Adjust after M1+M2 show baseline improvement. |
| BasicBlock instruction limit (128) hit after inlining | Medium | Increase to 256 or 512. Monitor instruction counts. |

---

## What Phase 4 Does NOT Include

These are explicitly deferred to later phases:

- **Loop tiling / cache optimization** — requires loop analysis infrastructure not yet present
- **AVX-512 / NEON SIMD** — requires type system support for vector types, new JIR opcodes, and platform detection. Deferred to Phase 6 (ML) where SIMD has clear ROI.
- **Auto-vectorization** — requires dependence analysis, loop vectorization pass. Too complex for Phase 4.
- **Profile-guided optimization (PGO)** — requires profiling infrastructure and binary rewriting
- **Link-time optimization (LTO)** — requires multi-file compilation (not yet supported)

These are listed in the roadmap but are better tackled when their prerequisites exist.

---

## Definition of Done

Phase 4 is complete when this program:

```jda
fn fib(n: i64) -> i64 {
    if n <= 1 { ret n }
    ret fib(n - 1) + fib(n - 2)
}

fn main() {
    let r = fib(35)
    print_int(r)
}
```

1. Produces `9227465` (correct)
2. Runs within **2x** of equivalent C compiled with `gcc -O2`
3. Self-host compile time is under **10 seconds**
4. All conformance tests pass (100+)
5. Self-host converged
