# Jda Compilation Strategy

Latest checkpoint: 2026-03-26

## Current Pipeline Status

1. `nasm` + `ld` -> `jda0`: passing
2. `jda0` compiles `bootstrap/stage1/jda1.jda` -> `jda1_a`: passing
3. `jda1_a` compiles `bootstrap/stage1/jda1.jda` -> `jda1_b`: blocked
4. `jda1_b` compiles `examples/hello.jda` -> `hello_sh`: blocked by step 3
5. `./hello_sh` -> `Hello Bare Metal`: blocked by step 4

## What Changed On This Branch

- The active lexer path now goes through `lex_small_fast()` instead of the heavier global lexer path during bootstrap.
- Dead or obsolete global-lexer helpers are skipped during bootstrap code generation so they do not break self-host progress.
- Parser-sensitive token accessor helpers were normalized into simpler wrapper forms that the live compiler can lower reliably.
- `skip_top_level_let_rhs`, `skip_top_level_let`, `parse_const_decl`, and `panic` were simplified to remove stage1 parser/codegen failures.
- Lowering fixup capacity was increased from `1024` to `8192`.
- Several bootstrap-only helpers and stub wrappers were flattened or skipped so stage 3 can progress deeper into the real parser/helper path.
- `init_top_jfn()` now performs real `JirFunction` initialization instead of only storing the source pointer.
- `.cline/` is now ignored in `.gitignore`.

## Bootstrap Policy

- Dead helpers may be skipped during bootstrap bring-up if they are not on the current self-host execution path.
- Useful live behavior must be preserved. Passing stage 3 by silently dropping real compiler capability is not acceptable.
- Tiny wrappers with one or two call sites may be inlined temporarily when that preserves behavior and isolates a source-shape bug.
- Broadly used live helpers should be fixed at the source-shape/compiler level instead of being removed.

## Current Blocker

- Stage 3 is still the active blocker on this branch.
- `jda1_a` now compiles much deeper into `bootstrap/stage1/jda1.jda`, but still stops with `if: expected {`.
- The current failing function is `parse_expr_stmt_tail()` in `bootstrap/stage1/jda1.jda`.
- The active issue is now in the parser expression-statement assignment tail after clearing the earlier `parse_expr_stmt_tail_*` dispatch wrappers.

## Strategy Going Forward

1. Keep `work/fix-selfhost-from-5e959be` as the clean debugging branch.
2. Continue stabilizing stage 3 on this clean branch until `jda1_a -> jda1_b` succeeds again.
3. Prioritize fixing the live parser/codegen source-shape issue in the current `parse_expr_stmt_tail_*` frontier before touching stage-4 work.
4. Once stage 3 passes again, rerun the full 5-step chain and then remove temporary debug prints and bootstrap-only skips that are no longer needed.

## Documentation Note

Several older status/todo docs were removed from the tree. This file and the current self-host status note are now the canonical references for bootstrap progress on this branch.
