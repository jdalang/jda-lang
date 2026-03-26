# Self-Host Status

Date: 2026-03-26
Branch: `work/fix-selfhost-from-5e959be`
Base commit: `5e959be55c01b51d2fc0a390aff6b26423792d27`

## Verified State

- `jda0` builds successfully.
- `jda0` compiles `bootstrap/stage1/jda1.jda` into `jda1_a`.
- `jda1_a` compiles `bootstrap/stage1/jda1.jda` into `jda1_b`.

## Current Failure

- `jda1_b` hangs while compiling `examples/hello.jda`.
- This means the current frontier has moved from stage 3 to stage 4.

## Key Branch Fixes

- Switched bootstrap lexing through `lex_small_fast()`.
- Skipped dead global-lexer helper codegen on the current bootstrap path.
- Added `tok_idx_in_range()` and normalized token accessor wrappers into simpler forms.
- Simplified parser-sensitive helpers:
  - `parse_const_decl`
  - `skip_top_level_let_rhs`
  - `skip_top_level_let`
  - `panic`
- Added `g_cur_fn_end` to enforce a hard per-function boundary during live block compilation.
- Increased `LowerCtx.fixups` from `1024` to `8192`.

## Remaining Work

1. Debug `jda1_b` on the `hello.jda` compile path.
2. Re-establish `jda1_b -> hello_sh`.
3. Re-run the full bootstrap pipeline end to end.
4. Remove temporary debug prints and bootstrap-only skips once the full chain is stable.
