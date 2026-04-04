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

### M2: Graph-Coloring Register Allocator

**Why second**: The current FIFO allocator with 7 registers generates excessive spill/reload pairs. This is the single biggest performance bottleneck. Every operation beyond 7 live values triggers a spill to memory.

**Current state**:
- `RegAlloc` struct: `pool[8]`, `val2reg[8192]`, `reg2val[8]`, `spill_off[8192]`
- 7 allocatable registers: RAX, RCX, RDX, RSI, RDI, R10, R11
- R12 reserved as scratch for syscalls/print
- RBX, R8, R9, R13-R15 unused by allocation (6 wasted registers)
- FIFO eviction: when all 7 are full, spills `pool[0]` regardless of future use

**Tasks**:
1. **Expand register pool** — add RBX, R8, R9, R13, R14, R15 to allocatable set (13 total)
   - Update `emit_save_pool()` / `emit_restore_pool()` to save/restore callee-saved registers (RBX, R12-R15)
   - Update `N_ALLOC_REGS` from 7 to 13
   - Fix any hardcoded assumptions about register numbering

2. **Liveness analysis** — compute live intervals for each SSA value
   - For each basic block, walk instructions in reverse to find first-use and last-use
   - Build `live_start[val_id]` and `live_end[val_id]` arrays
   - Handle cross-block liveness (values defined in one block, used in another)

3. **Interference graph** — build register conflict matrix
   - Two values interfere if their live ranges overlap
   - Compact representation: bitset per value (8192 values × 8192 bits = 8MB, or use sparse)
   - For v1: use simple sorted-interval approach instead of full adjacency matrix

4. **Linear scan allocation** (upgrade from FIFO to proper linear scan)
   - Sort intervals by start point
   - Maintain active set of currently-live intervals
   - When register needed: expire ended intervals, pick free register, or spill longest-range value
   - This is simpler than full graph coloring and good enough for most code

5. **Spill cost heuristic** — prefer spilling values with few uses and long ranges
   - Count uses per value (already done in `lower_fn_collect_uses`)
   - Spill the value with lowest `uses / range_length` ratio

6. **Verify correctness** — self-host convergence, all conformance tests pass

**Expected impact**: 20-40% fewer spill/reload instructions. Significant speedup for register-heavy functions (codegen, lowering). Binary size reduction from fewer spill instructions.

**Risk**: Medium-high. Register allocation bugs cause silent wrong-code generation. Need extensive testing. Keep old allocator as fallback behind `-O0` flag.

---

### M3: Function Inlining

**Why third**: After register allocation is improved, inlining becomes the next biggest win. The compiler has ~170 small helper functions (emit_byte, modrm_rr, tok_type_at, etc.) that are called thousands of times. Each call costs: push args → CALL → prologue → body → epilogue → RET → pop result. For 1-3 instruction bodies, the overhead exceeds the work.

**Tasks**:
1. **Inline candidate detection**
   - Count instructions per function during JIR generation
   - Mark functions as "inlineable" if: ≤ 8 JIR instructions, no recursion, single basic block, ≤ 3 parameters
   - Store inline threshold as a compiler constant (tunable)

2. **Call site expansion**
   - When `codegen_call_inline` / `live_codegen_call_inline` encounters a call to an inlineable function:
   - Instead of emitting OP_CALL, copy the function's JIR instructions into the caller's basic block
   - Rename all value IDs to avoid conflicts (offset by caller's current instruction count)
   - Replace OP_RET with assignment to the result value

3. **Inline depth limit** — prevent infinite expansion
   - Maximum inline depth of 2 (inline A into B, but don't inline into the inlined copy)
   - Maximum expansion factor: if inlining would add >64 instructions, skip

4. **Inlining heuristics**
   - Always inline: `emit_byte`, `modrm_rr`, `mod8`, `mod256`, `i32_b0`-`i32_b3`, `tok_type_at`, `tok_str_start_at`, `tok_str_len_at`
   - Never inline: `lower_fn`, `live_compile_block`, `main`, recursive functions
   - Cost model: `call_overhead - inline_size > threshold` → inline

5. **Post-inline optimization** — re-run fold_constants + dce on inlined code

**Expected impact**: 30-50% reduction in CALL/RET instruction pairs. Enables further optimization of inlined code (constant propagation through inlined helpers). May increase code size — monitor binary bloat.

**Risk**: Medium. Inlining can increase code size and register pressure. Need binary size monitoring. The JIR basic block limit (128 instructions per block) may be hit — may need to increase.

---

### M4: Tail-Call Optimization

**Why fourth**: Recursive patterns in the compiler (parser, codegen, lowering all recurse through expression trees) currently grow the stack per call. With 524MB stack ulimit, this works but is wasteful. TCO makes recursion O(1) stack.

**Tasks**:
1. **Detect tail calls** — a CALL immediately followed by RET with the call's result
   - In JIR: scan for `%r = OP_CALL ...` followed by `OP_RET %r` as the last two instructions in a basic block
   - Also detect self-recursive tail calls: `fn foo() { ... ret foo() }`

2. **Transform self-recursive tail calls** into loops
   - Replace `OP_CALL self` + `OP_RET` with: reassign parameters + `OP_JMP` to function entry block
   - This avoids the CALL instruction entirely

3. **General tail calls** — reuse caller's stack frame
   - Move arguments into parameter positions
   - Pop saved registers
   - JMP instead of CALL (no return address pushed)
   - x86-64: requires careful stack manipulation in lowering

4. **Mutual tail calls** (stretch) — `foo() -> bar() -> foo()` chains
   - Requires interprocedural analysis — defer to v2 if complex

**Expected impact**: Eliminates stack growth for recursive parsers and tree walkers. Enables purely recursive algorithms without stack overflow risk. Small binary size reduction (JMP < CALL+RET).

**Risk**: Low-medium. Self-recursive TCO is straightforward. General tail calls require careful stack frame management. Start with self-recursive only.

---

### M5: Peephole Optimization

**Why fifth**: After higher-level optimizations are in place, peephole catches the low-hanging x86-64 patterns that the lowering pass generates.

**Tasks**:
1. **MOV elimination**
   - `MOV rax, rbx; MOV rbx, rax` → delete second MOV
   - `MOV rax, rax` → delete (NOP)
   - `MOV rax, rbx; <op> rax` → `<op> rbx` (if rax dead after)

2. **Strength reduction**
   - `IMUL rax, 2` → `SHL rax, 1`
   - `IMUL rax, 4` → `SHL rax, 2`
   - `IMUL rax, 8` → `SHL rax, 3` (common for array indexing: `idx * 8`)
   - `DIV by power-of-2` → `SHR`

3. **Address mode fusion**
   - `MOV rax, [rbx]; ADD rax, 8; MOV rcx, [rax]` → `MOV rcx, [rbx + 8]`
   - x86-64 supports `[base + disp32]` addressing — use it

4. **Compare-and-branch fusion**
   - `CMP rax, 0; JE target` → `TEST rax, rax; JE target`
   - `SUB rax, rbx; JE target` → omit separate CMP (SUB sets flags)

5. **Constant folding in lowering**
   - `MOV rax, 0` → `XOR rax, rax` (smaller encoding)
   - `ADD rax, 0` → delete
   - `IMUL rax, 1` → delete

6. **Implementation approach** — post-lowering pass over emitted bytes
   - Two options: (a) pattern-match on JIR before lowering, or (b) pattern-match on x86 bytes after
   - Prefer (a) — work at JIR level where patterns are clearer
   - Add a `peephole()` pass between `dce()` and lowering

**Expected impact**: 5-10% speedup from reduced instruction count. Significant improvement for array-heavy code (struct field access = base + offset * 8).

**Risk**: Low. Peephole patterns are local and easily tested. Each pattern is independent.

---

### M6: Benchmark Suite

**Why last**: Need all optimizations in place before measuring against C/Rust/Go. Benchmarking before optimization just measures the bottleneck, not the language.

**Tasks**:
1. **Micro-benchmarks** — measure individual operations
   - Integer arithmetic loops (1M iterations of add/mul/div)
   - Array traversal (sum 1M i64 array)
   - Struct field access (traverse linked list)
   - Function call overhead (1M calls to trivial function)
   - String operations (concatenation, search)
   - Memory allocation (arena alloc vs malloc vs mmap)

2. **Compiler benchmarks** — measure real compiler performance
   - Time to compile jda1.jda (self-compile benchmark)
   - Time to compile each conformance test
   - Instructions executed per source line (perf stat)
   - Cache miss rate (perf stat L1/L2/L3)

3. **Cross-language comparison programs**
   - **Fibonacci** (naive recursive) — measures call overhead + TCO
   - **Sieve of Eratosthenes** — measures array access + branches
   - **JSON parser** — measures string handling + struct allocation
   - **Matrix multiply** (100×100) — measures arithmetic throughput
   - **Binary tree** (GC benchmark) — measures allocation + deallocation
   - Write each in Jda, C (gcc -O2), Rust (release), Go

4. **Benchmark infrastructure**
   - `jda bench` subcommand — runs all benchmarks, outputs table
   - Compare against baseline (store previous results)
   - Track regressions across commits

5. **Performance targets**

   | Benchmark | Target vs C -O2 | Stretch |
   |-----------|-----------------|---------|
   | Fibonacci | ≤ 2x slower | ≤ 1.5x |
   | Sieve | ≤ 3x slower | ≤ 2x |
   | JSON parse | ≤ 5x slower | ≤ 3x |
   | Matrix mul | ≤ 3x slower | ≤ 2x |
   | Self-compile | < 10 seconds | < 5 seconds |

**Expected impact**: Credibility. Published benchmarks showing Jda within 2-3x of C prove the language is viable for performance-sensitive work.

**Risk**: Low. Benchmarks don't change compiler code. Risk is in unrealistic targets — adjust after initial measurements.

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
