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
- the old `FN#59` string-close helper blocker is gone
- `lex_handle_string(...)` is now reduced to helper calls for:
- `lex_set_pos_ptr(...)`
- `lex_mark_string_start()`
- `lex_skip_string_body()`
- `lex_emit_marked_string()`
- `lex_sync_pos_ptr(...)`
- selfhost now gets past `FN#59`
- `lex(...)` now uses the global token output pointer consistently (`g_lex_out_toks`) with a 2-arg signature
- fixed `lex_handle_minus(...)` lookahead read so `->` is tokenized as `TOK_ARROW` again
- removed the temporary selfhost-only `Token` struct sanity gate that blocked normal user programs
- selfhost now reaches and enters `FN#60` body, but still fails later in that function
- removed the hottest expression/call trace prints (`EXPRST`, `cu*`, `call arg*`) from stage-1 inline codegen paths to reduce clobber risk in the failing window

3. Current Blocker
Status: 🟡 active

🟡 Active blocker:
- `jda1 -> jda1_sh2` still fails before producing `jda1_sh2`
- stage-1 self-compile now gets much farther (through `F#60` and into later functions), but is still unstable in late parse/codegen paths
- latest frequent failure windows are in higher `F#` ranges (`F#8x` and beyond), with many parser mismatches and eventual crash
- even when `SELF_EXIT:0` occurs, produced `jda1_sh2` is malformed and segfaults on `hello.jda`

🟡 Latest evidence:
- panic output now prints real strings plus token position/type/span context
- top-level parser now reliably reaches function parsing (`F#0..`) before failure
- live parser path was hardened to re-read tokens from global token pointer each loop
- `live_compile_if(...)`/`live_compile_loop(...)` now use direct token checks (not `expect(...)`) for brace boundaries
- old `FN#24` `TOK_DOT` non-advance blocker is cleared
- old `FN#60`/`FN#61` hard-stop blockers were pushed forward; current failures are later-stage parse/codegen corruption and fixup instability
- unresolved call fixups are still observed, and output ELF metadata remains invalid in failed selfhost outputs

🟡 Why it matters:
- stage 0 remains healthy (`make clean all stage1` passes)
- stage 1 still compiles and runs `hello.jda` (`Hello Bare Metal`)
- the remaining selfhost blocker is now late-stage stability (parse/codegen/fixup consistency) before final selfhost artifact validity

4. Next fix
Status: 🟡 next

🟡 Work in order:
- keep the current helper-based lexer baseline
- keep the stable `32 x 128` block-storage layout
- once `./jda1 ../stage1/jda1.jda jda1_sh2` completes again, re-run the full hello roundtrip immediately

🟡 Concrete next edits:
- keep the current lexer fixes (`TOK_ARROW`, `g_lex_out_toks`) unchanged
- remove remaining ad-hoc recovery hacks that can corrupt later IR/fixups
- harden late compile paths (`codegen_expr_inline` / postfix / call args) to avoid invalid token/field fallthrough
- stabilize call-fixup resolution and unresolved-call behavior so generated code remains executable
- keep debug probes minimal and targeted (only around the active crash window) to reduce clobber risk
- keep optimizer passes disabled until raw selfhost compilation is stable

🟡 Expected outcome of next fix:
- produce a structurally valid `jda1_sh2` (no malformed ELF / no immediate segfault)
- complete `./jda1 ../stage1/jda1.jda jda1_sh2`
- then run `jda1_sh2 -> hello_sh2` successfully

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
