Strategy

1. Stage 0 bootstrap stability
Status: ✅ done

✅ Done:
- moved large stage-0 buffers off `.bss` and onto `mmap`
- fixed the `gen_stmt` stack leak
- fixed `gen_fn` frame-size patch ordering
- fixed stage-0 pointer handling needed for selfhost bring-up
- fixed stage-0 global typed struct-pointer codegen for helper/global access paths

✅ Verified:
- `jda0` builds and runs
- `jda0 -> jda1 -> hello.jda` works
- current hello output is `Hello Bare Metal`
- stage 0 now patches `main` correctly for the current `jda1.jda` again
- the minimal global `&Token` repro now works through helper writes and reads (`11 / 22 / 33 / 44`)

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
- added bounds-guarded token access in `parse_const_decl(...)` and `skip_top_level_let(...)` to avoid out-of-range reads during top-level scans
- added top-level `fn` header guard so malformed `TOK_FN` sequences without an identifier are skipped instead of entering function compile
- added a minimal inline `asm { ... }` skip path so stage-1 `main()` no longer dies immediately on `asm { out argv_ptr = rsi }`
- seeded `argv_ptr` from `rsi` in lowered stage-1 `main()` so the skipped inline `asm` still preserves argv behavior
- fixed skipped-function resync so legacy/parser functions now scan forward to the next top-level `fn`/`let` using the same raw-text fallback as the main top-level loop
- simplified `emit_lea_rip(...)` so selfhost now gets past that previous top-level frontier

✅ Verified:
- `jda0 -> jda1 -> hello.jda` works again after the recent source changes
- `jda0 -> jda1_a -> hello.jda -> hello_out` now works again and prints `Hello Bare Metal`
- `jda1_a -> jda1_b` can now complete and patch `main` correctly on successful runs
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
- `make selfhost-stage1` still passes on Docker after the latest parser hardening (`Hello Bare Metal`)
- `make ci-selfhost-roundtrip` still segfaults at `stage1_a -> stage1_b` (exit `139`)
- the old `jda1_b exits 0 without writing hello output` symptom is gone; after the stage-1 `main()`/`asm` fix it now reaches runtime and segfaults instead of silently doing nothing
- successful `jda1_a -> jda1_b` runs now get much further through top-level function compilation after the skipped-function resync fix, moving the frontier from the old `parse_*` cluster into later lowering/live-codegen helpers
- the top-level scanner now reliably reaches the real end of file (`... syscall(...)\n}`), so the earlier “premature EOF” suspicion was ruled out
- the current top-level frontier has moved past `emit_lea_rip(...)` into later helpers, and the latest runtime crash signal on `hello` points at the `live_codegen_primary_inline(...)` band

3. Current Blocker
Status: 🟡 active

🟡 Active blocker:
- the old stage-0 global token-pointer miscompile is fixed, and stage-1 `main()` now executes far enough to print path/write probes, but `jda1_a -> jda1_b` is still intermittent
- successful self-compile runs now reach `PH done_top`, patch `main`, write `jda1_b`, and then `jda1_b` crashes while compiling `hello.jda`
- the latest compile-time frontier moved out of the old parser band and into later lowering/live-codegen helpers, with recent progress through `emit_call_rel32`, `emit_lea_rip`, and nearby helpers
- the latest runtime clue from `jda1_b ../../examples/hello.jda ...` is a partial `prim t=` print, pointing at `live_codegen_primary_inline(...)` as the next exact crash window

🟡 Latest evidence:
- the dedicated stage-0 repros showed the real root cause was global `&Token` field/index access through helpers
- after the stage-0 fix, `jda1_a` again tokenizes `hello.jda`, finds `main`, patches entry, and emits a working `hello_out`
- adding the stage-1 `asm` skip + `argv_ptr` seed changed `jda1_b` from “exit 0 without output” to a real runtime crash, which confirms the earlier emitted-`main`/silent-noop bug was real and is now past us
- fixing skipped-function resync moved successful `jda1_a -> jda1_b` runs from stopping near the legacy `parse_*` cluster to stopping much later in the lowering/live-codegen band
- the remaining failure is still intermittent rather than a single deterministic `FN#` stop, which points to another runtime/codegen stability bug rather than the earlier fixed token-pointer or empty-`main` bug

🟡 Why it matters:
- stage 0 remains healthy (`make clean all stage1` passes)
- stage 1 again compiles and runs `hello.jda` (`Hello Bare Metal`) from `jda1_a`
- the remaining selfhost blocker is now intermittent `jda1_a -> jda1_b` stability plus the later `jda1_b -> hello.jda` runtime crash before final roundtrip validation

4. Next fix
Status: 🟡 next

🟡 Work in order:
- keep the fixed stage-0 typed-global path and the current helper-based lexer baseline
- keep the stable `32 x 128` block-storage layout
- keep the new skipped-function resync and `main()`/`asm` handling fixes
- make `jda1_a -> jda1_b` deterministic again before trusting any later `jda1_b -> hello` result

🟡 Concrete next edits:
- keep the current stage-0 global metadata fix unchanged
- keep the current skipped-function resync logic unchanged
- use the named `CFN` trace to map the intermittent self-compile crash window to exact later helper functions
- narrow the next failing band around `emit_lea_rip(...)`, `live_codegen_primary_inline(...)`, and nearby live-codegen helpers instead of making broad parser edits
- keep debug probes minimal and targeted (only around the active crash window) to reduce clobber risk
- keep optimizer passes disabled until raw selfhost compilation is stable

🟡 Expected outcome of next fix:
- make `jda1_a -> jda1_b` complete reliably, not just intermittently
- then stabilize the current `jda1_b -> hello.jda` crash
- then proceed to the final selfhost roundtrip

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
