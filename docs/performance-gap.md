# Why Jda Is Slower Than C — and How to Close the Gap

Jda compiles directly to native machine code with no C dependency, yet
benchmarks show a 1.5–3.5x gap against clang -O2 on most workloads.
This document lists every known root cause, ranked by impact, with a
concrete task for each one.

---

## Current Benchmark Baselines (macOS ARM64 / Rosetta 2, April 2026)

| Benchmark | C (clang -O2) | Jda (pre-LS) | Jda (linear-scan) | Ratio  | Status        |
|-----------|---------------|--------------|-------------------|--------|---------------|
| sudoku    | 52 ms         | 19 ms        | 19 ms             | **2.7x faster** | Jda wins |
| lz77      | 2758 ms       | 287 ms       | 283 ms            | **9.7x faster** | Jda wins |
| regex     | 188 ms        | 190 ms       | 102 ms            | **1.8x faster** | Jda wins (+46%) |
| btree     | 375 ms        | 593 ms       | 558 ms            | 1.5x slower | gap narrowing |
| raytracer | 42 ms         | 145 ms       | 90 ms             | 2.1x slower | SIMD gap (-38%) |

---

## Root Causes (ranked by impact)

---

### 1. Round-Robin Register Allocator  ✅ DONE (linear-scan hints, April 2026)

**Impact: raytracer -38% (145→90ms), regex -46% (190→102ms), btree -6% (593→558ms)**

Implemented linear-scan pre-assignment: compute `[first_def, last_use]` intervals
for every value, assign pool slots greedily in definition order, use as hints in
the online `regalloc_alloc`. The online allocator still runs but now prefers the
pre-assigned slots, reducing eviction churn on long-lived values.

**Tasks completed:**
- Task A: ✅ `lower_fn_collect_uses` extended to record `g_val_first_def[vid]`
- Task B: ✅ `linear_scan(jfn)` assigns `g_ls_reg[val_id]` as hint; `regalloc_alloc` checks hint first
- Task C: ✅ Coalescing pass — `coalesce_copies_block` in `copy_prop` loop (April 2026).
  Substitutes OP_COPY(dst, src) → replaces all subsequent uses of dst with src in-block,
  letting DCE kill the dead OP_COPY. Convergence constraint: peephole context diverges
  (jda0 function-size limit); only copy_prop context converges. Inliner-created OP_COPYs
  not reachable from copy_prop context, so btree impact is ~0% (inlining already handled).
  `linear_scan` also updated to skip dead instructions (prevents dead OP_COPYs from
  evicting live register hints). 390/395 tests pass, sh2==sh3 (2,082,575 bytes).

**Files:** `linear_scan`, `ls_assign`, `ls_expire`, `regalloc_alloc`
(bootstrap/stage1/jda1.jda ~14700–14800)

**Remaining gap:** btree still 1.5x C. Full coalescing or graph-coloring allocator
would close it further. SIMD is the remaining blocker for raytracer (now 2.1x C).

---

### 2. No SIMD / Auto-Vectorization  ✅ DONE (SLP Phase 1+2+3 + OP_BITCAST, April 2026)

**Impact: raytracer 2.1x gap (SIMD + I2F conversion cost)**

Clang auto-vectorizes loops like `for i { a[i] += b[i] }` into 4-wide
or 8-wide AVX2/AVX-512 instructions. A single `vaddps ymm0, ymm1, ymm2`
processes 8 floats in the time one `addss xmm0, xmm1` processes one.

The raytracer inner loop computes dot products, cross products, and
reflection vectors — all trivially vectorizable. Jda emits one scalar
`FADD/FMUL` per element.

**SLP (Superword-Level Parallelism) implemented:**
- OP_F64X2_BIN = 100: new JIR opcode for SSE2 packed f64×2
- `slp_vectorize` detects adjacent identical FADD/FSUB/FMUL/FDIV pairs
  whose operand pairs are adjacent LOAD_MEM (same base, offset+8)
- Emits MOVUPD (128-bit load) + ADDPD/SUBPD/MULPD/DIVPD
- Fires for struct/array adjacent-field f64 access patterns (raw float bits in memory)
- **Phase 3 (broadcast, April 2026):** also fuses `FMUL(LOAD_MEM[base,off], const)` +
  `FMUL(LOAD_MEM[base,off+8], const)` where both ops share the same scalar constant.
  Emits MOVUPD + UNPCKLPD (broadcast) + MULPD.
- **Fundamental limit for raytracer:** all sphere data goes through `I2F(LOAD_MEM)` 
  (integers stored scaled by 0001, converted via CVTSI2SD). MOVUPD loads raw bits —
  it cannot substitute for CVTSI2SD. Closing this gap requires AVX-512 VCVTQQ2PD
  or explicit scalar+pack sequences.

**Remaining tasks:**
- Task A: Detect reduction loops (`acc = acc OP a[i]`) and emit
  horizontal SIMD (vhaddps / vpermilps).
- Task B: Add AVX2 f64×4 and f32×8 loop patterns to the peephole /
  lowering pipeline.
- Task C: AVX-512 VCVTQQ2PD to vectorize I2F(LOAD_MEM) pairs (closes raytracer gap).

---

### 3. No Inlining of Hot Callees  ✅ DONE (splicer active, all ops inlined, April 2026)

**Impact: 5x upper bound measured on accessor-heavy code (April 2026)**

Every function call costs: 6 argument-register moves, a `call`
instruction (indirect branch prediction miss on first call), a frame
setup, and 6 callee-save push/pops. For tiny 1–3 line helpers called
millions of times per second, the call overhead dominates.

The splicer (Phase 2) is unparked and running. OP_DIV/OP_MOD are now
allowed as inline candidates. The fix: track `has_div` flag per entry;
only inline into blocks with no non-inlinable calls (prevents IDIV
clobbering RAX/RDX in mixed-call contexts). OP_MUL remains guarded by
`is_mul_setter` check (regalloc drift bug not yet root-caused).

**Status (April 2026):**
- ✅ Task A: OP_DIV/OP_MOD inlining — `has_div` guard at `base+13`, uses
  `inline_block_has_non_inline_call` (IDIV clobbers RAX/RDX). 393/393 pass.
- ✅ Task B: OP_MUL — `is_mul_setter` guard removed; IMUL (3-operand) does not
  clobber RDX. 393/393 pass, sh2==sh3 (2,076,476 bytes).
- ✅ Task C: Splicer active for all arithmetic ops. Hot accessors in sudoku/btree/
  regex inline freely. Dead-code guards removed; alignment-safe.

**Files:** `inline_capture_meta`, `inline_splice_block`, `inline_op_arith_ok`
(bootstrap/stage1/jda1.jda ~13758–14270)

---

### 4. Intra-Block Copy Propagation Only

**Impact: 10–20% on loop-heavy code with multi-block data flow**

Jda's copy-prop (OP_COPY pass) tracks slot→value mappings within each
basic block and resets them at block boundaries. This means a value
computed in the loop header is re-loaded at every iteration start even
if no store intervened.

GCC does **global** dataflow (reaching definitions, available
expressions) across all blocks in a function. A value defined in block A
remains available in block B as long as no store to that slot is
reachable between A and B.

**What to build:**
- Task A: Compute reaching-definitions sets per block (gen/kill
  bitvectors, standard iterative dataflow).
- Task B: Extend cp_scan_block to seed the initial slot→value map from
  the reaching-definitions of the block's predecessors (intersect on
  join points).
- Task C: Run global copy-prop before DCE.

**Files:** `copy_prop`, `cp_scan_block`, `cp_init_slots`
(bootstrap/stage1/jda1.jda ~12800)

---

### 5. No Instruction Scheduling

**Impact: 5–15% on pipelines with high instruction latency (e.g., loads)**

Modern out-of-order CPUs can execute independent instructions in
parallel, but they need the compiler to separate a high-latency
instruction (L1 cache load: 4 cycles) from the instruction that
consumes its result. Jda emits instructions in the order they appear in
the IR, which can produce stall chains like:

```asm
movq (%rax), %rcx    ; load — 4 cycle latency
addq %rcx, %rdx      ; STALL: waiting 4 cycles for %rcx
```

GCC schedules the load earlier and fills the gap with independent work.

**What to build:**
- Task A: Build a dependency graph over instructions in a basic block
  (which instruction produces the input of which other instruction).
- Task B: Topological-sort the graph using a priority queue that
  prefers scheduling high-latency ops (loads, multiplies) as early as
  possible.
- Task C: Apply after register allocation (post-RA scheduling) to avoid
  invalidating register assignments.

---

### 6. No Global Dead Code Elimination

**Impact: binary size, minor speed improvement via I-cache**

Jda's DCE is intra-block: it marks instructions whose results are never
used within the same block. Instructions whose result flows to a
different block (phi-equivalent or cross-block use) are conservatively
kept alive even if the final consumer is unreachable.

GCC marks a whole function dead if it has no callers, and eliminates
dead stores across blocks.

**What to build:**
- Task A: Build a call graph. Mark functions with no callers as dead.
  (Already partially done for inliner candidate detection.)
- Task B: Extend DCE to track cross-block use counts using the
  reaching-definitions framework (shares work with task 4).

---

### 7. Naive Spill Slot Assignment

**Impact: stack frame bloat, extra memory traffic**

When a value is spilled, Jda assigns it to `sp_top += 8` — a new slot
every time. If a value's lifetime ends before another value is spilled,
the dead slot is never reused. Large functions accumulate hundreds of
spill slots, blowing up the stack frame and reducing cache density of
live spill values.

**What to build:**
- Task A: Track spill slot liveness (freed when use_cnt reaches 0).
- Task B: Maintain a free-list of released spill slots. On new spill,
  prefer a free slot before growing sp_top.

**Files:** `ra_set_sp_top`, spill assignment in `emit_save_pool`
(bootstrap/stage1/jda1.jda ~14900)

---

### 8. No Profile-Guided Optimization (PGO)

**Impact: 5–20% on branch-heavy code**

GCC can instrument a binary, run it, collect branch frequency data, and
recompile with that data to:
- Lay out hot basic blocks contiguously (reduces I-cache misses).
- Convert unpredictable branches to conditional moves (CMOV) when
  one path dominates.
- Inline callees that are hot at a specific call site but not globally.

Jda has no instrumentation or feedback loop.

**What to build:**
- Task A: Add rdtsc-based basic-block counters to a debug build mode.
- Task B: Emit a profile data file after execution.
- Task C: On a second compile pass, use the profile to reorder blocks
  and guide inlining decisions.

---

## Quick-Win Tasks (1–2 days each)

These don't require the large passes above but give measurable gains:

| Task | Expected Gain | Complexity |
|------|--------------|------------|
| Fix OP_DIV in splicer (unblocks inlining) | 5–20% on accessor code | Medium |
| Spill slot free-list reuse | 2–5% (cache density) | Small |
| Global dead function elimination | Binary size, I-cache | Small |
| Loop alignment for promoted loops (revisit after stack-layout pinning) | 2–10% | Medium |
| Extend copy-prop across loop back-edges | 5–10% on loop-heavy | Medium |

---

## Architecture Summary

```
Source .jda
   │
   ▼
Lexer → Parser → JIR (SSA-like IR)
   │
   ▼
Optimization Pipeline (per function):
  copy_prop     ← intra-block only (gap: global)
  fold_constants
  dce           ← intra-block only (gap: global)
  tail_call_opt
  peephole      ← strength reduction, LEA, MOD→AND, MULQ
   │
   ▼
Lowering (JIR → x86-64 machine code):
  regalloc      ← round-robin (gap: linear-scan)
  emit_*        ← direct byte emission, no scheduling
  loop_promote  ← R13/R14/R15 for hot loop counters
   │
   ▼
ELF / Mach-O binary
```

The two biggest levers in order: **linear-scan regalloc** (closes btree gap),
then **SIMD vectorization** (closes raytracer gap), then **inlining** (closes
sudoku/regex remaining overhead).
