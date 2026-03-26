# Jda Compilation Strategy

Latest checkpoint: 2026-03-26

## Current Pipeline Status

1. `nasm` + `ld` -> `jda0`: passing
2. `jda0` compiles `bootstrap/stage1/jda1.jda` -> `jda1_a`: passing
3. `jda1_a` compiles `bootstrap/stage1/jda1.jda` -> `jda1_b`: passing
4. `jda1_b` compiles `examples/hello.jda` -> `hello_sh`: blocked
5. `./hello_sh` -> `Hello Bare Metal`: blocked by step 4

## What Changed On This Branch

- `jda1_a` is stable again. The stage-3 self-host step now completes successfully.
- The active lexer path now goes through `lex_small_fast()` instead of the heavier global lexer path during bootstrap.
- Dead or obsolete global-lexer helpers are skipped during bootstrap code generation so they do not break self-host progress.
- Parser-sensitive token accessor helpers were normalized into simpler wrapper forms that the live compiler can lower reliably.
- `skip_top_level_let_rhs`, `skip_top_level_let`, `parse_const_decl`, and `panic` were simplified to remove stage1 parser/codegen failures.
- Lowering fixup capacity was increased from `1024` to `8192`.
- `.cline/` is now ignored in `.gitignore`.

## Current Blocker

- `jda1_b` now starts and runs, but hangs while compiling `examples/hello.jda`.
- The immediate next task is stage-4 debugging on `jda1_b`, not more stage-3 stabilization.

## Strategy Going Forward

1. Keep `work/fix-selfhost-from-5e959be` as the clean debugging branch.
2. Treat stage 3 as re-established and avoid reopening that work unless a stage-4 fix regresses it.
3. Instrument `jda1_b` on the `hello.jda` path and isolate the first loop or token/parse state that stops making progress.
4. Once `jda1_b -> hello_sh` passes, rerun the full 5-step chain and then remove temporary debug prints and dead-code skips that are no longer needed.

## Documentation Note

Several older status/todo docs were removed from the tree. This file and the current self-host status note are now the canonical references for bootstrap progress on this branch.
