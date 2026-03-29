# Jda Compilation Strategy

Latest checkpoint: 2026-03-27

## Current Pipeline Status

1. `nasm` + `ld` -> `jda0`: passing
2. `jda0` compiles `bootstrap/stage1/jda1.jda` -> `jda1_a`: passing
3. `jda1_a` compiles `bootstrap/stage1/jda1.jda` -> `jda1_b`: blocked
4. `jda1_b` compiles `examples/hello.jda` -> `hello_sh`: blocked by step 3
5. `./hello_sh` -> `Hello Bare Metal`: blocked by step 4
Ideall Approach
1. Fix jda1_a -> jda1_b so jda1_b is stable.
2. Make jda1_a and jda1_b byte-identical.
so if jda1_a compile byte different and jda1_b compile byte totally different or compile pattern different. then something is wrong in pur compilation between jda1_a and jda1_a compile result jda1_b
- jda1_a emits one machine-code shape
- jda1_b emits a different machine-code shape
- jda1_a and jda1_b have different SHA-256 hashes
why jda1_a have different machine code and jda1_b have different, is we are not using JVM?
so when jda1_a compile jda1_b, it need to use same SHA-256 hashes, which uses to compile jda1_a
No JVM is involved here. This is native self-hosting.

  What should happen is:

  1. jda0 compiles jda1.jda -> jda1_a
  2. jda1_a compiles the same jda1.jda -> jda1_b
  3. if the compiler is correct and deterministic, jda1_b should be byte-identical to jda1_a

  So yes: jda1_a should compile jda1.jda into the same bits as the ones that produced jda1_a’s behavior. Not because it “uses the same SHA”, but because both compilers should implement the same semantics and codegen.
  Why they differ right now:
  - jda0 and jda1_a are not behaving equivalently yet for some stage1 constructs
  - or jda1_a miscompiles parts of jda1.jda
  - or codegen is nondeterministic / order-dependent
  - in practice here, it looks like miscompilation, not harmless nondeterminism
  SHA-256 is only the check. It is not an input to compilation.
  The important invariant is:
  - same source in
  - same compiler semantics
  - same output binary out
If that invariant holds, then sha256(jda1_a) == sha256(jda1_b).
If it does not hold, then self-hosting is still broken. That is exactly the state now.
3. Then rerun jda1_b -> hello_sh.

## What Changed On This Branch

- The active lexer path now goes through `lex_small_fast()` instead of the heavier global lexer path during bootstrap.
- Dead or obsolete global-lexer helpers are skipped during bootstrap code generation so they do not break self-host progress.
- Parser-sensitive token accessor helpers were normalized into simpler wrapper forms that the live compiler can lower reliably.
- `skip_top_level_let_rhs`, `skip_top_level_let`, `parse_const_decl`, and `panic` were simplified to remove stage1 parser/codegen failures.
- Lowering fixup capacity was increased from `1024` to `8192`.
- Several bootstrap-only helpers and stub wrappers were flattened or skipped so stage 3 can progress deeper into the real parser/helper path.
- `init_top_jfn()` now performs real `JirFunction` initialization instead of only storing the source pointer.
- `.cline/` is now ignored in `.gitignore`.
- A misplaced skip-codegen guard for `lookup_slot_name` was fixed so stage 3 can bypass that dead source-definition compile path correctly.
- The live self-host expression path was pushed through `live_codegen_binop_*`, `live_codegen_postfix_*`, `live_codegen_primary*`, and `live_codegen_call_inline`.
- The allocator and emitter path was pushed through `reg_pool_at`, `regalloc_alloc`, `regalloc_get`, `regalloc_free`, `mark_use`, `consume_use`, and a long run of x86 emission helpers through `emit_save_pool`.
- The lowering path was pushed through:
  - `get_or_load`
  - `lower_syscall*`
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
- The live lowering route now goes through `lower_instr_callalloc2()`, while the older `lower_instr_callalloc()` wrapper is skipped during stage-3 codegen.

## Bootstrap Policy

- Dead helpers may be skipped during bootstrap bring-up if they are not on the current self-host execution path.
- Useful live behavior must be preserved. Passing stage 3 by silently dropping real compiler capability is not acceptable.
- Tiny wrappers with one or two call sites may be inlined temporarily when that preserves behavior and isolates a source-shape bug.
- Broadly used live helpers should be fixed at the source-shape/compiler level instead of being removed.

## Current Blocker

- Stage 3 is still the active blocker on this branch.
- `jda1_a` now compiles much deeper into `bootstrap/stage1/jda1.jda`, but still stops with `if: expected {`.
- The current failing function is `lower_instr_callalloc2()` in `bootstrap/stage1/jda1.jda`.
- The active issue is now in the late lowering dispatcher path after clearing the earlier parser, live-expression, allocator, emitter, and most lowering helper frontiers.

## Strategy Going Forward

1. Keep `work/fix-selfhost-from-5e959be` as the clean debugging branch.
2. Continue stabilizing stage 3 on this clean branch until `jda1_a -> jda1_b` succeeds again.
3. Prioritize fixing the live lowering source-shape issue in the current `lower_instr_callalloc2()` frontier before touching stage-4 work.
4. Once stage 3 passes again, rerun the full 5-step chain and then remove temporary debug prints and bootstrap-only skips that are no longer needed.

## Documentation Note

Several older status/todo docs were removed from the tree. This file and the current self-host status note are now the canonical references for bootstrap progress on this branch.
