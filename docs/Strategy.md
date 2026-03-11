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
- split `char_to_tok(...)` into smaller helpers
- split `classify_keyword(...)` into length-based helpers
- factored most of `lex(...)` into smaller helper functions
- rewrote the remaining hot `skip_top_level_let(...)` indexed RHS through helpers so the old bare-`[` bug there is cleared
- simplified `parse_type(...)` into a straighter-line shape to reduce parser-state fragility

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
- the temporary `BIND_OVF 32` failure in `skip_top_level_let(...)` is gone after the `inc_i64_at0(...)` rewrite
- the old `skip_top_level_let(...)` bare-`[` blocker is gone
- selfhost now reaches `FN#45`
- the old `char_to_tok(...)`, `classify_keyword(...)`, and main `lex(...)` helper-pressure blockers are no longer the immediate failure
- the old `regalloc_init(...)` crash after `J4` is fixed
- the old `FN#0` `ret ct.names_len[idx]` postfix/index crash is fixed
- selfhost now gets through far later helper/lowering functions before failing
- exact token dumps are now available for mapping failing windows directly back to source
- the current `FN#52` / `lex_handle_int(...)` token window has been identified and partially simplified

3. Current bug
Status: active blocker

Current failure:
- `jda1 -> jda1_sh2` still fails before producing `jda1_sh2`
- the current crash is still in the live stage-1 selfhost compiler path, not stage 0 and not final ELF emission
- the latest failure has moved much later than before and is no longer the old post-`FN#45` function-boundary theory
- `regalloc_init(...)` now survives consistently; the crash moved past the old `J4` lowerer setup point
- the current active failure is in the function currently traced as `FN#52`
- exact token mapping shows that this region corresponds to `lex_handle_int(...)`
- latest bounded trace reaches:
  - `FN#52`
  - `loop keep == 1`
  - `if pos[0] >= src_len { ... }`
  - then later statement parsing in the same function drifts into garbage around token positions `4446..4455`
  - latest panic is after:
    - `EXPRST p=4446`
    - then corrupted token values at `p=4447+`
- this indicates the active bug is now a statement-boundary / token-buffer corruption issue inside `lex_handle_int(...)` or its immediate token-emission path, not the earlier broad function-boundary parse theory

Meaning:
- stage 0 is healthy enough for bring-up again
- the active work is still stabilizing the stage-1 live parser/codegen on real `jda1.jda` source patterns
- the current highest-signal area is small lexer helper code, especially:
  - `lex_handle_int(...)`
  - token emission into `out_toks[count]`
  - simple loops/ifs that still mix nested index expressions and helper calls

4. Next fix
Status: next

Work in order:
- finish simplifying the active `FN#52` / `lex_handle_int(...)` body
- keep the stable `32 x 128` block-storage layout
- once `./jda1 ../stage1/jda1.jda jda1_sh2` completes again, re-run the full hello roundtrip immediately

Concrete next edits:
- keep flattening `lex_handle_int(...)` off nested token/index/helper-call shapes until its statement stream stays aligned
- simplify token emission paths that still write through `out_toks[count[0]].field`
- keep direct token-window dumps for the failing range instead of inferring from `FN#` numbering alone
- keep `EMIT_SLOT`, `FN#`, and parse-error traces only as long as needed to move past the current function
- keep the optimizer passes disabled until raw selfhost compilation is stable
- only after `jda1_sh2` is produced, revisit optimizer and cleanup work

Expected outcome of next fix:
- get past the current `FN#52` failure in `lex_handle_int(...)`
- move the blocker to the next concrete function/source form, not a broad parser corruption report

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
