# Self-Host Status

Date: 2026-03-26
Branch: `work/fix-selfhost-from-5e959be`
Base commit: `5e959be55c01b51d2fc0a390aff6b26423792d27`

## Verified State

- `jda0` builds successfully.
- `jda0` compiles `bootstrap/stage1/jda1.jda` into `jda1_a`.
- `jda1_a` does not yet compile the full `bootstrap/stage1/jda1.jda` into a stable `jda1_b`.

## Current Failure

- The active blocker is still stage 3: `jda1_a -> jda1_b`.
- The current failure frontier is `parse_expr_stmt_tail_field_dispatch_hi()` in `bootstrap/stage1/jda1.jda`.
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

## Bring-Up Guardrails

- Dead helpers may be skipped if they are not on the current bootstrap execution path.
- Useful live behavior must be preserved; stage-3 bring-up should not reduce actual compiler capability.
- Tiny wrappers may be inlined temporarily when that preserves semantics and avoids a known source-shape failure.
- Broadly used live helpers should be fixed, not removed.

## Remaining Work

1. Continue stage-3 stabilization until `jda1_a -> jda1_b` succeeds again.
2. Fix the live source-shape issue in the `parse_expr_stmt_tail_*` assignment-field dispatch path.
3. Re-establish the full self-host loop through `jda1_b`.
4. Then retest `jda1_b -> hello_sh` and rerun the full bootstrap pipeline end to end.
