Strategy

1. Stage 0 bootstrap stability
Status: ✅ done

Done:
- moved large stage-0 buffers off `.bss` and onto `mmap`
- fixed the `gen_stmt` stack leak
- fixed `gen_fn` frame-size patch ordering
- fixed stage-0 pointer handling needed for selfhost bring-up

Verified:
- `jda0` builds and runs
- `jda0 -> jda1 -> hello.jda` works
- current hello output is `Hello Bare Metal`
- stage 0 now patches `main` correctly for the current `jda1.jda` again

2. Stage 1 selfhost progress
Status: partially done

✅ Done:
- removed the earlier top-level global recorder crash
- added minimal top-level global tracking for stage 1
- extended `OP_CALL` handling from 3 args to 6 args
- replaced fragile const-table struct storage with flat global const arrays
- added early const sanity checking so startup const failures surface immediately
- fixed several expression/codegen blockers:
- postfix field/index handling now moves much further
- unary `-1` no longer crashes
- stage-1 call parsing no longer breaks obvious postfix arguments like `x[i]` and `obj.field`
- preserved struct element type across `[...]`, fixing forms like `toks[pos[0]].type`
- flattened several fragile nested call-argument forms in top-level parsing
- added fast paths for simple terminal expressions and simple comparisons
- removed raw `~` operator uses from `jda1.jda` so stage 0 can scan the whole file again
- removed the unsupported `break` in `lex(...)`
- added live lowering for `arr[idx].field = rhs`
- temporarily disabled `fold_constants` and `dce` during selfhost bring-up
- removed the stage-0 `streq(...)` hot-path crash by replacing the per-function `main` check with a direct guarded compare
- flattened more of `lex(...)` off fragile compound boolean forms
- added a fast path for `ident = ident +/- int`
- extended those fast paths to cover `let` / assignment forms using `ident +/- ident|int` and `ident */ ident|int`
- fixed pointer-to-struct element typing in the field/index paths used by `out_toks[count].field`
- flattened the remaining `helper(src[pos])` call-argument shapes in `lex(...)`
- flattened `parse_const_decl(...)` and `skip_top_level_let(...)` to stop carrying local `Token` structs just to read `str_start` / `str_len`
- identified a real per-basic-block instruction cap during selfhost codegen (`EMIT_SLOT 64 bb=0`) and raised the block instruction budget conservatively to `128`

Verified:
- `jda0 -> jda1 -> hello.jda` works again after the recent source changes
- stage 0 pass 1 now records `main` and stage 0 pass 2 patches the startup call for `jda1`
- selfhost gets through const parsing and struct parsing (`A/B/C/D`)
- selfhost gets through many top-level `let` records again
- the earlier infinite loop at `expect(..., TOK_CONST)` is gone
- startup constant lookup now works
- selfhost gets through multiple helper calls and struct/array expressions that used to fail much earlier
- `./jda1 ../stage1/jda1.jda jda1_sh2` no longer fails on the old stage-0 `main` patch bug
- the old `lex(...)` call-argument crash at `EXPRST p=2978` / `call arg p=2986` is gone
- the `64`-instruction basic-block limit was confirmed as a real blocker
- the `256`-instruction experiment was too large and caused an immediate startup crash, so `128` is the current working ceiling

3. Current bug
Status: active blocker

Current failure:
- `jda1 -> jda1_sh2` still fails before producing `jda1_sh2`
- the current crash is back in the live stage-1 selfhost compiler path, not stage 0 and not final ELF emission
- the latest failure is now earlier again, at `FN#0`, which is `const_name_len_at(...)`
- recent traces narrowed failures to:
  - the old `lex(...)` call-argument blocker has been cleared
  - the per-block instruction cap was too small at `64`
  - the next active bug is back in postfix field/index lowering for `ident.field[idx]`-style return expressions
- latest bounded trace reaches:
  - `FN#0`
  - `ret1 p=981`
  - `ce p=981`
  - `prim enter p=981`
  - `prim next p=982 t=33`
  - `prim lookup p=981`
  - then dies while compiling the return expression for `ct.names_len[idx]`

Meaning:
- the old “stage-2 binary emission is the primary blocker” theory is no longer current
- stage 0 is healthy enough for bring-up again
- the active work is still stabilizing the stage-1 live parser/codegen on real `jda1.jda` source patterns
- especially in:
  - helper return expressions like `ct.names_len[idx]`
  - postfix field/index lowering for `ident.field[idx]`
  - keeping the per-block instruction budget large enough for selfhost without blowing up `JirFunction` stack footprint

4. Next fix
Status: next

Work in order:
- debug the `const_name_len_at(...)` return expression path first
- keep the `128` instruction cap unless it proves too small again
- once `./jda1 ../stage1/jda1.jda jda1_sh2` completes again, re-run the full hello roundtrip immediately

Concrete next edits:
- map the exact failing postfix path for `ct.names_len[idx]` in `const_name_len_at(...)`
- fix `ident.field[idx]` lowering if the field-array path is still losing type or address information
- keep the `EMIT_SLOT` trace until the `128` cap is proven sufficient across early helper functions
- if needed, flatten `const_name_len_at(...)` / similar helpers to simpler locals before widening the parser again
- keep the optimizer passes disabled until raw selfhost compilation is stable
- only after `jda1_sh2` is produced, revisit optimizer and cleanup work

Expected outcome of next fix:
- get `./jda1 ../stage1/jda1.jda jda1_sh2` to complete again
- move the blocker back to `jda1_sh2 -> hello` or to the next specific source form, rather than a broad stage-1 crash

5. Final testing
Status: pending

Selfhost is complete only if both pass:

Step 1:
```sh
./jda1 ../stage1/jda1.jda jda1_sh2
```

Step 2:
```sh
./jda1_sh2 ../../examples/hello.jda hello_sh2 && ./hello_sh2
```

Expected output:
```text
Hello Bare Metal
```

Issue 10 should be marked done only after both steps pass in Docker/Linux without the debug loop or crash.
