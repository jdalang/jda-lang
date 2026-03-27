# Self-Host Status

Date: 2026-03-27
Branch: `work/fix-selfhost-from-5e959be`
Base commit: `5e959be55c01b51d2fc0a390aff6b26423792d27`

## Verified State

- `jda0` builds successfully.
- `jda0` compiles `bootstrap/stage1/jda1.jda` into `jda1_a`.
- `jda1_a` does not yet compile the full `bootstrap/stage1/jda1.jda` into a stable `jda1_b`.

## Current Failure

- The active blocker is still stage 3: `jda1_a -> jda1_b`.
- The current failure frontier is `lower_instr_callalloc2()` in `bootstrap/stage1/jda1.jda`.
- The exact current failure is `if: expected {` while compiling deeper parser/helper code.

## Key Branch Fixes

- Switched bootstrap lexing through `lex_small_fast()`.
- Skipped dead global-lexer helper codegen on the current bootstrap path.
- Added `tok_idx_in_range()` and normalized token accessor wrappers into simpler forms.
- Simplified parser-sensitive helpers:
  - `parse_const_decl`
  - `skip_top_level_let_rhs`
  - `skip_top_level_let`
  - `panic`
- Flattened or skipped a long run of bootstrap-only stub helpers so stage 3 can keep moving through the real parser path.
- Replaced stubbed `init_top_jfn()` logic with real `JirFunction` field initialization.
- Added `g_cur_fn_end` to enforce a hard per-function boundary during live block compilation.
- Increased `LowerCtx.fixups` from `1024` to `8192`.
- Fixed a misplaced skip-codegen guard for `lookup_slot_name`.
- Cleared the live self-host expression path through:
  - `live_codegen_binop_inline`
  - `live_codegen_binop_rest`
  - `live_codegen_postfix_inline`
  - `live_codegen_postfix_rest`
  - `live_codegen_primary2_inline`
  - `live_codegen_primary_small_inline`
  - `live_codegen_primary_paren_inline`
  - `live_codegen_primary_ident_inline`
  - `live_codegen_call_inline`
- Cleared the lowering/allocator/emitter path through:
  - `reg_pool_at`
  - `regalloc_alloc`
  - `regalloc_get`
  - `regalloc_free`
  - `mark_use`
  - `consume_use`
  - x86 emit helpers through `emit_save_pool`
  - `get_or_load`
  - `lower_syscall_push_arg`
  - `lower_syscall_pop_arg`
  - `lower_syscall_consume_arg`
  - `lower_syscall`
  - `lower_instr_rip_fixup`
  - `lower_instr_constlike`
  - `lower_instr_mem`
  - `lower_instr_arith`
  - `lower_instr_cmpbit`
  - `lower_branch_fixup`
  - `lower_instr_ctrl`
  - `lower_instr_alloc`
  - `lower_instr_call`
  - `lower_instr_call_args`
  - `lower_instr_call_emit`
- Added `lower_instr_callalloc2()` and routed the live lowering path through it, while the older `lower_instr_callalloc()` wrapper is skipped during stage-3 codegen.
- Skipped the dead `legacy_compile_*` fallback cluster from bootstrap codegen.

## Bring-Up Guardrails

- Dead helpers may be skipped if they are not on the current bootstrap execution path.
- Useful live behavior must be preserved; stage-3 bring-up should not reduce actual compiler capability.
- Tiny wrappers may be inlined temporarily when that preserves semantics and avoids a known source-shape failure.
- Broadly used live helpers should be fixed, not removed.

## Remaining Work

1. Continue stage-3 stabilization until `jda1_a -> jda1_b` succeeds again.
2. Fix the live source-shape issue in `lower_instr_callalloc2()` after clearing the parser, live-expression, allocator, emitter, and most lowering helper frontiers.
3. Re-establish the full self-host loop through `jda1_b`.
4. Then retest `jda1_b -> hello_sh` and rerun the full bootstrap pipeline end to end.
