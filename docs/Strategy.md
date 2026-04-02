# Jda Compilation Strategy

Latest checkpoint: 2026-04-02

## Current Pipeline Status — SELF-HOSTING CONVERGED

1. `nasm` + `ld` -> `jda0`: passing
2. `jda0` compiles `bootstrap/stage1/jda1.jda` -> `jda1`: passing
3. `jda1` compiles `bootstrap/stage1/jda1.jda` -> `jda1_sh2` (1,770,427 bytes): passing
4. `jda1_sh2` compiles `bootstrap/stage1/jda1.jda` -> `jda1_sh3` (1,769,979 bytes): passing
5. `jda1_sh3` compiles `bootstrap/stage1/jda1.jda` -> `jda1_sh4` (1,769,979 bytes): passing
6. `jda1_sh3 == jda1_sh4`: **IDENTICAL** — fixed-point convergence achieved

The compiler is fully self-hosting. `jda1_sh3` is the first binary that reproduces itself exactly.

## Key Fixes That Enabled Convergence

### Unconditional `loop {}` miscompilation
`loop { ... }` without a condition was miscompiled: `codegen_expr_inline` returned -1 for the missing condition, causing `emit_br` to branch on whatever garbage was in RAX. If RAX happened to be 0, the loop body was skipped entirely. Fixed by converting all 7 instances to `loop var == 1 { ... }` with explicit condition variables.

### Direct indexed byte store miscompilation
`out[idx + N] = i32_bN(val)` in the OP_STRLEN lowering path was miscompiled in the self-hosted output, causing SIGSEGV/SIGILL. Fixed by replacing with `poke_byte(out, idx + N, val)` function calls.

### rex_byte() 4-argument call miscompilation
`rex_byte(w, r, x, b)` was miscompiled when called with 4 arguments. Fixed by inlining the REX byte computation at all 18 call sites: `let rex = 64 + w*8 + r_hi*4 + x*2 + b_hi`.

### Prior fixes (accumulated over multiple sessions)
- Dangling AST pointers: added codegen_expr_inline (Pratt parser, emits JIR directly)
- Constants unresolved: added global const tables, lookup_const
- Block/instr limits raised (BasicBlock[256], Instr[128])
- Stack overflow: JirFunction/LowerCtx allocated once outside main loop
- argv clobber: read rsi before any print() call
- Dangling Token pointer in NODE_LET
- Struct literal consumed as `x{}` in `if x {}`
- else-if-else chains: trailing else properly consumed

## Known Workarounds in jda1.jda

These patterns are required because jda0 miscompiles certain constructs:

- **No unconditional `loop {}`** — must use `loop var == 1 {}` with explicit condition
- **No direct `out[idx] = val` byte stores in lowering** — must use `poke_byte()` wrapper
- **No `rex_byte()` function calls** — 4-arg calls miscompiled; inline the computation

## Bootstrap Policy

- Dead helpers may be skipped during bootstrap bring-up if they are not on the current self-host execution path.
- Useful live behavior must be preserved. Passing stages by silently dropping real compiler capability is not acceptable.
- Tiny wrappers with one or two call sites may be inlined temporarily when that preserves behavior and isolates a source-shape bug.

## Strategy Going Forward

1. Self-hosting is achieved. `jda1_sh3` is the converged compiler.
2. Next steps: use the self-hosted compiler as the foundation for language improvements.
3. The workarounds above can be removed once jda0 is no longer needed (i.e., once jda1 is the bootstrap compiler).
