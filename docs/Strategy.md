Strategy

1. Stage 0 bootstrap stability
Status: ✅ done

✅ Done:
- moved large stage-0 buffers off `.bss` and onto `mmap`
- fixed the `gen_stmt` stack leak
- fixed `gen_fn` frame-size patch ordering
- fixed stage-0 pointer handling needed for selfhost bring-up

✅ Verified:
- `jda0` builds and runs
- `jda0 -> jda1 -> hello.jda` works
- current hello output is `Hello Bare Metal`
- stage 0 now patches `main` correctly for the current `jda1.jda` again

2. Stage 1 selfhost progress
Status: 🟡 in progress

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

✅ Verified:
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
- the old `lex_handle_int(...)` signature-parser failure is fixed
- top-level param parsing now uses raw token spans instead of local `Token` copies
- `compile_let_inline(...)` now binds names by raw span instead of a local `Token`
- `peek_token(...)` now reads through `tok_type_at(...)`
- `codegen_call_inline(...)` now uses raw token metadata for the callee name and delimiter checks
- `lex_handle_string(...)` and `emit_lex_tok(...)` were moved off the fragile `out_toks[count[0]].field` write shape
- `lex_handle_int(...)` has been simplified repeatedly to remove unstable `let ... = call(...)`, `ret call(...)`, and some nested index forms
- the `ident[ident]` postfix fast path in `codegen_postfix_inline(...)` was hardened to use raw token metadata and raw-span lookup
- targeted fast paths were added for `let ident = ident[index]` and `ident = ident[index]`
- the `p0` setup in `lex_handle_int(...)` is no longer the immediate blocker
- the `load_i8_at0(src, pos)` comparison path now gets through
- the indexed token writes in `lex_handle_int(...)` now route through `tok_set_int_at(...)`
- direct `count[0]` RHS loads in `lex_handle_int(...)` were replaced with `load_i64_at0(count)`
- selfhost now reaches `FN#54`
- `compile_let_inline(...)` now has a direct fast path for `let name = helper(...)` so simple call RHS forms can bypass the more fragile generic expression path
- `lex_handle_int(...)` was reworked to a no-early-return loop shape so digit parsing now has a single final emit path instead of repeated emit-and-return blocks inside the loop
- integer scanning is now split into a one-parameter `lex_scan_int(pos)` helper backed by lexer globals
- the digit loop inside `lex_scan_int(...)` now uses a simpler `if / else if / else` chain
- `lex_handle_int(...)` is now reduced to a let-call plus a one-parameter emit helper
- the old `==` mis-tokenization in `lex_skip_string_body(...)` is fixed
- the old `>=` mis-tokenization in `skip_top_level_let(...)` is fixed
- the old `!=` mis-tokenization in `streq(...)` / `try_escape(...)` is fixed
- the operator-handler condition overconsume in `lex_handle_minus(...)`, `lex_handle_eq(...)`, `lex_handle_bang(...)`, `lex_handle_gt(...)`, and `lex_handle_lt(...)` is fixed by hoisting the `load_i64_at0(pos)` result before comparing with `g_lex_src_len`
- `lex_skip_string_body(...)` is now reduced to a one-parameter global-backed helper
- `lex_handle_string(...)` now routes the closing-quote tail through `lex_maybe_close_string(...)`
- selfhost now gets past the operator-handler cluster and into the later string helper path
- the string-scan path now uses a global index (`g_lex_pos_i`) with:
- `lex_set_pos_ptr(...)`
- `lex_skip_string_body()`
- `lex_maybe_close_string()`
- `lex_sync_pos_ptr(...)`
- the current best local form of `lex_maybe_close_string()` gets through:
- the outer bounds check
- `let idx = g_lex_pos_i`
- `let cur = g_lex_src_ptr[idx]`
- the remaining branch-local increment is still the active edge

3. Current Blocker
Status: 🟡 active

🟡 Active blocker:
- `jda1 -> jda1_sh2` still fails before producing `jda1_sh2`
- the old `FN#54` `lex_handle_int(...)` blocker is no longer the active one
- the active blocker has narrowed further inside the later string-helper band
- the current best checkpoint is now `FN#59`, which maps to `lex_maybe_close_string()`
- the remaining unstable shape is inside the closing-quote helper, after the indexed character load already succeeds

🟡 Latest evidence:
- rewriting `lex_emit_str(...)` to direct token-field stores was a regression and was reverted
- the global-index string-scan path moves farther than the earlier direct `pos`-mutation variants
- the current best trace gets through:
- `lex_skip_string_body(...)`
- `lex_maybe_close_string(...)`
- the operator-handler cluster
- and now fails late inside `lex_maybe_close_string()`, not on the earlier operator-token bugs
- the current best local form keeps:
- `let idx = g_lex_pos_i`
- `let cur = g_lex_src_ptr[idx]`
- and still treats the final increment as the remaining active edge

🟡 Why it matters:
- stage 0 is healthy enough for bring-up again
- several earlier lexer/runtime blockers are now behind us:
- the old `==`, `>=`, and `!=` tokenization failures
- the operator-handler condition overconsume
- the old inline closing-quote index shape in `lex_handle_string(...)`
- the current highest-signal area is now the reduced closing-quote helper, which is narrower than the older monolithic lexer failures

4. Next fix
Status: 🟡 next

🟡 Work in order:
- keep the current helper-based lexer baseline
- keep the stable `32 x 128` block-storage layout
- once `./jda1 ../stage1/jda1.jda jda1_sh2` completes again, re-run the full hello roundtrip immediately

🟡 Concrete next edits:
- keep the current operator-handler fixes and reduced string helpers in place
- keep the helper-based `lex_emit_str(...)` baseline, not the regressing direct-store rewrite
- keep the current global-index string-scan path in place
- continue simplifying the remaining branch tail in `lex_maybe_close_string()` until that helper is clear
- keep using raw token-window dumps for the failing range instead of inferring from `FN#` numbering alone
- keep `EMIT_SLOT`, `FN#`, and parse-error traces only as long as needed to move past the current function
- keep the optimizer passes disabled until raw selfhost compilation is stable
- only after `jda1_sh2` is produced, revisit optimizer and cleanup work

🟡 Expected outcome of next fix:
- get past the remaining `lex_maybe_close_string()` branch-tail instability
- move the blocker beyond the current string-helper band to the next concrete source form

5. Final testing
Status: ⏳ pending

⏳ Selfhost is complete only if both pass:

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
