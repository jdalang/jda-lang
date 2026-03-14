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
- rebalanced `JirFunction` block storage to `32 x 128` so the larger per-block budget does not immediately blow up startup stack usage
- replaced the temp-heavy `pos` increment rewrites in `skip_top_level_let(...)` with `inc_i64_at0(...)`
- flattened the remaining `let ... = pos[0]` reads in `skip_top_level_let(...)` to `load_i64_at0(pos)`
- confirmed and cleared the temporary `BIND_OVF 32` local-table exhaustion caused by the earlier temp-heavy flattening

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
- the `32 x 128` block-storage rebalance moves selfhost past the old `FN#0` `ct.names_len[idx]` crash
- selfhost now reaches `FN#10`
- the temporary `BIND_OVF 32` failure in `skip_top_level_let(...)` is gone after the `inc_i64_at0(...)` rewrite

3. Current bug
Status: active blocker

Current failure:
- `jda1 -> jda1_sh2` still fails before producing `jda1_sh2`
- the current crash is back in the live stage-1 selfhost compiler path, not stage 0 and not final ELF emission
- the latest failure is now later, at `FN#10`, which is `skip_top_level_let(...)`
- recent traces narrowed failures to:
  - the old `FN#0` `ct.names_len[idx]` blocker has been cleared by the block-storage rebalance
  - the `skip_top_level_let(...)` local-table overflow introduced by earlier flattening is fixed
  - the next active bug is a partially consumed indexed shape that leaves a bare `[` token behind
- latest bounded trace reaches:
  - `FN#10`
  - several `EXPRST` call statements in `skip_top_level_let(...)`
  - then:
    - `EXPRST p=1772 t=10 n=23`
    - `EXPRST p=1777 t=17 n=10`
    - `ce p=1777`
    - `cu p=1777 t=17`
  - which means a statement in `skip_top_level_let(...)` is still leaving a raw `[` token behind for the next expression path

Meaning:
- the old “stage-2 binary emission is the primary blocker” theory is no longer current
- stage 0 is healthy enough for bring-up again
- the active work is still stabilizing the stage-1 live parser/codegen on real `jda1.jda` source patterns
- especially in:
  - `skip_top_level_let(...)`
  - indexed token / bracket-consumption paths in top-level global/type parsing
  - keeping the `32 x 128` block-storage layout unless a later function proves it insufficient

4. Next fix
Status: next

Work in order:
- identify the exact `skip_top_level_let(...)` statement that still leaves the bare `[` token behind
- keep the `32 x 128` block-storage layout unless it proves too small again
- once `./jda1 ../stage1/jda1.jda jda1_sh2` completes again, re-run the full hello roundtrip immediately

Concrete next edits:
- use the new `EXPRST` traces to map the exact `skip_top_level_let(...)` statement behind `p=1772..1777`
- flatten that remaining indexed/bracket source shape so it fully consumes the `[` / `]`
- keep `BIND_OVF` and `EMIT_SLOT` traces until `skip_top_level_let(...)` and the next few functions are stable
- if necessary, replace one more `pos[0]`-derived statement with a helper instead of adding new locals
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
