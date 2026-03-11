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
- fixed pointer-to-struct element typing in the field/index paths used by `out_toks[count].field`

Verified:
- `jda0 -> jda1 -> hello.jda` works again after the recent source changes
- stage 0 pass 1 now records `main` and stage 0 pass 2 patches the startup call for `jda1`
- selfhost gets through const parsing and struct parsing (`A/B/C/D`)
- selfhost gets through many top-level `let` records again
- the earlier infinite loop at `expect(..., TOK_CONST)` is gone
- startup constant lookup now works
- selfhost gets through multiple helper calls and struct/array expressions that used to fail much earlier
- `./jda1 ../stage1/jda1.jda jda1_sh2` no longer fails on the old stage-0 `main` patch bug
- selfhost now reaches `FN#24`, which is `lex(...)`
- the earlier `out_toks[count].type = ...` / simple `count = count + 1` blockers have been pushed forward

3. Current bug
Status: active blocker

Current failure:
- `jda1 -> jda1_sh2` still fails before producing `jda1_sh2`
- the current crash is back in the live stage-1 selfhost compiler path, not stage 0 and not final ELF emission
- the latest failure is later than before, inside `FN#24` (`lex(...)`)
- recent traces narrowed failures to:
  - unsupported source shapes inside `lex(...)`
  - later call-argument / indexed-expression handling inside `lex(...)`
  - remaining fallback expression paths after the earlier field-store and simple-assignment fixes
- latest bounded trace reaches:
  - `EXPRST p=2978`
  - `call p=2985`
  - `call arg p=2986`
  - then dies while entering the generic primary-expression path for that call argument

Meaning:
- the old “stage-2 binary emission is the primary blocker” theory is no longer current
- stage 0 is healthy enough for bring-up again
- the active work is still stabilizing the stage-1 live parser/codegen on real `jda1.jda` source patterns
- especially in:
  - `lex(...)`
  - later fallback expression parsing after `lex(...)` branch rewrites
  - call arguments that still force the generic expression path
  - remaining pointer/struct indexing edge cases

4. Next fix
Status: next

Work in order:
- map the latest `FN#24` (`lex(...)`) call-argument / fallback-expression crash
- keep flattening unsupported `lex(...)` source shapes in `jda1.jda` instead of deepening the parser when a source rewrite is cheaper
- once `./jda1 ../stage1/jda1.jda jda1_sh2` completes again, re-run the full hello roundtrip immediately

Concrete next edits:
- identify the exact `lex(...)` statement behind the latest `EXPRST` / `call arg` token window
- map tokens `2978..2986` back to the concrete source line in `lex(...)`
- flatten that source shape to avoid the generic fallback expression path
- if the failing arg is another nested `toks[...]` / field / index form, rewrite it into locals before the call
- add one more narrow trace in the call-argument path only if the source mapping is still ambiguous
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
