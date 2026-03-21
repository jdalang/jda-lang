Strategy

Latest checkpoint (2026-03-16, session 5 — spill collision fixed, fn-scan segfault):

✅ Done in session 5:
- confirmed root cause of const-loop infinite spin: **register spill / local-slot collision**
  - jda1's regalloc starts spill slots at `[rbp-8]`, `[rbp-16]`, …
  - local variables (via `alloc_slot`) also started at small positive offsets from 0, which after
    negation landed in the same range — spills overwrote locals on every allocation
  - fix: `jfn.next_slot_off = 65536` in the function-reset block (line 6165) pushes ALL local
    variable slots beyond the spill zone (`[rbp-65544]` and down); spills stay in `[rbp-8..72]`
  - the fix was already in jda1.jda but jda1_sh2_new was stale (compiled before the fix);
    rebuild (jda0→jda1→jda1_sh2_new) confirmed it resolves the TKCNT_ZERO / CI infinite loop
- confirmed jda1_sh2_new now reaches and passes POST-CONST and STRDONE ✅
  - const-parsing loop exits correctly after processing all `const` declarations
  - struct-parsing loop exits correctly after processing all `struct` declarations
- identified next crash: segfault in the fn-name scan loop
  (`loop scan_pos < tok_cnt`) inside jda1_sh2_new's `main()`; crash occurs mid-loop, after
  many SL iterations, before SCAN_DONE — exact crash point not yet pinned

🔴 Current blocker — segfault inside fn-scan loop in jda1_sh2_new

### What happens
jda1_sh2_new processes jda1.jda through LEX, const-scan, and struct-scan successfully.
It then enters the fn-name scan loop (`loop scan_pos < tok_cnt`). The loop runs many
iterations (SL prints) but crashes with SIGSEGV before the loop exits. SCAN_DONE never
prints.

### Candidates
- **A — tok_type_at / tok_str_start_at / tok_str_len_at OOB**: `scan_pos` might exceed a valid
  index into `toks` if `tok_cnt` is wrong (e.g., stale local slot with wrong value), causing
  `toks[scan_pos]` to read unmapped memory.
- **B — fn_name_off store OOB**: if `fn_cnt` is wrong (slot collision), the guard `fn_cnt < 512`
  might not fire and `fn_name_off[fn_cnt]` writes past the 4 KB alloc_pages(1) buffer.
- **C — streq null dereference**: `streq(src_buf, t_start, 2, "fn")` — if `t_start` is 0 or
  out-of-range for `src_buf`, the byte reads inside `streq` could fault.
- **D — residual slot collision in scan body**: the scan body locals (`t`, `t_start`, `t_len`,
  `name_idx`) are compiled with `jfn.next_slot_off = 65536` but if any intermediate spill still
  lands in the local zone, it could corrupt a pointer.

🟡 Next work:
- add print("SCAN_BODY\n") inside each branch of the scan loop to pin the crash to a specific
  statement
- print tok_cnt (as char by printing each digit via syscall) to verify the value is correct
  (~44000 expected); if it's garbage, the local-slot for tok_cnt is wrong
- print fn_cnt after each fn discovery to verify it stays < 512
- once SCAN_DONE fires: check alloc_pages for code/strtab/glob buffers, then the main compile
  loop (LOOPCHECK / FENTER / POSTLOWER sequence)

---

Latest checkpoint (2026-03-16, session 4 — selfhost inline-compile bring-up):

✅ Done in session 4:
- fixed `lower_syscall(...)`: syscall result was clobbered by `emit_restore_pool` before the dst
  register received it; fix: save RAX→R12 immediately after `syscall`, then `emit_restore_pool`,
  then `regalloc_alloc(dst)`, then move R12→dst; bracketed with `push R12`/`pop R12` (R12 is
  callee-saved and not in the pool so restore never touches it)
- fixed `main()` argv setup: old code used `asm { out base_ptr = rbp }` + `base_ptr + 24`; the
  asm block was silently skipped by `compile_asm_argv_inline` (only handles "rsi"), leaving
  base_ptr=0 and causing a segfault at `g_argv_base[1]`; fix: use `asm { out argv_ptr = rsi }`
  which maps to OP_ARGV_BASE → `lea rax, [rbp+16]` (correct for both JMP-style jda1 binaries
  and CALL-style jda0 binaries when the asm is handled directly by jda0's assembler)
- removed all `print(integer_var)` debug calls from `main()`: in jda1-compiled binaries, `print`
  treats its arg as `&i8` → calls `OP_STRLEN(int)` = `strlen(9)` → SIGSEGV; only string literal
  `print("...")` calls are safe
- confirmed jda1_sh2_new now gets through: "A / JDA1_START / J1..J7 / LEX DONE" ✅

🔴 Current blocker — const loop infinite in jda1_sh2_new

### What happens
jda1_sh2_new processes jda1.jda correctly up to "LEX DONE" (lex runs on 216 KB of real source,
returns ~44 K tokens). Then the const-parsing loop (`loop more_consts == 1`) runs forever:
`CI` prints indefinitely, never exiting.

### Root cause candidates
The loop body assigns `more_consts = 0` in two else-branches, but the value never persists:

**Candidate A — variable scope / shadowing**: `more_consts` is declared OUTSIDE the loop in
`main()`. Inside nested if/else blocks compiled by `compile_stmts_inline`, the assignment
`more_consts = 0` goes through `compile_expr_stmt2_inline` → `lookup_slot_name`. If the
JirFunction's var table is full (VarEntry[128]) or the lookup fails, the store is silently
skipped and `more_consts` stays 1 forever.

**Candidate B — loop condition SSA**: The loop head block evaluates `more_consts == 1` by
emitting `OP_LOAD(slot_of_more_consts)` in `head_blk`. If the lowered code for `OP_LOAD`
loads from the wrong stack offset, it always reads the initial value (1).

**Candidate C — block limit**: `main()` is a very large function with many nested blocks
(each `if`, `loop` creates new basic blocks). If `create_block_live` hits the BasicBlock[256]
limit, blocks reuse or corrupt existing blocks, breaking control flow.

### Key difference from old jda1_sh2
The OLD jda1_sh2 (compiled by jda1_new before lower_syscall fix) had broken syscall result
capture, so `src_len` was garbage (likely 0). With src_len=0, lex returned tok_cnt=0, and all
loops (`more_consts`, `more_structs`) exited immediately on `pos < tok_cnt` check. The NEW
jda1_sh2_new has correct src_len=216618, so the loops actually execute with real data and the
`more_consts = 0` assignment must work correctly.

🟡 Next work:
- Check if `main()` exceeds VarEntry[128] before the const loop (main has many locals before it)
- Add a print inside the `else { more_consts = 0 }` path to confirm whether that branch executes
- Check if `lookup_slot_name` finds `more_consts` (add a print in compile_expr_stmt2_inline on
  slot==-1 path)
- If var table is full: increase VarEntry[128] → VarEntry[256] in JirFunction struct
- If block limit: add block_cnt overflow panic and test; may need BasicBlock[512]
- Once const loop exits: check struct loop, function compile loop

---

Latest checkpoint (2026-03-15, session 3 — jda0 P2 crash investigation):

⚠️  Upstream changes to `jda0.asm` and `jda1.jda` introduced a new regression:
`make stage1` (jda0 → jda1_new) now segfaults in jda0's Pass 2 at function index 97.

✅ Context from session 2 (preserved for reference):
- fixed stage-1 `main()` stack overflow: `JirFunction{}` + `LowerCtx{}` moved outside main loop
- fixed argv clobber: `asm { out argv_ptr = rsi }` must precede any `print()` call
- confirmed `jda1_new → jda1_sh2` exits 0, produces ~721 KB binary ✅
- added `OP_ARGV_BASE = 31` opcode for correct argv capture in write_elf-compiled binaries
- `jda1_sh2 → jda1_sh3` exits 0, produces output ✅
- expanded token buffer: 65535 → 131071
- session 2 blocker (now superseded): `print(integer)` causes OP_STRLEN segfault in write_elf
  compiled binaries because `compile_print_inline` always treats the arg as `&i8`

🔴 Current blocker — jda0 crashes in P2 at function 97 (`parse_let`):

### Crash symptoms
- `make stage1` exits 139 (SIGSEGV) in jda0 Pass 2
- P2 debug output: `P2 0123456789+++...+` — exactly 97 characters printed → crash at function 97
- Function 97 (0-indexed) = `parse_let` (jda1.jda line 1846)
- Function 96 (`parse_block`) compiled successfully; crash is in the first function after it

### Register state (extracted from ELF core dump)
```
RIP = 0x0000000020000000   ← cod_buf start (jda0's mmap'd code output buffer, COD_BUF_CAP=16 MB)
r15 = 0xffff80001fc60b92   ← corrupted (kernel-space address, impossible user value)
r14 = 0x81 (= 129)
rbp = 0x00007ffffffffbf0
rbx = 0x00007ffffffffbf8  ← rbp+8 (points to the return address slot in gen_fn's frame)
rsp = 0x0000efffffff8000   ← valid given 500 MB ulimit stack shift
```

### Root cause hypothesis
`gen_fn`'s return address on jda0's execution stack was overwritten with the cod_buf pointer
value (0x20000000).  When `gen_fn` executes `ret`, it pops 0x20000000 into RIP and jumps to
the start of the generated-code buffer — which contains the machine code emitted for jda1.jda
function 0 (`ok`), not a valid return continuation.

Evidence:
- RIP == cod_buf_ptr exactly (0x20000000 is mmap'd at that address with `MAP_FIXED`)
- rbx == rbp+8 (return address slot is at rbp+8 in gen_fn; unusual but observed in frame layout)
- r15 is corrupted — r15 is used as a scratch register in `.ges_call` (`mov r15, [rax+40]`
  for code_off) but is NOT saved/restored by gen_fn, so any caller that depends on r15 across
  a gen_fn call would see the clobbered value

### What was ruled out
- Stale jda0_structs.asm: already reflects `Instr[256]` (BasicBlock=24600 bytes) ✅
- Stale jda0_constants.asm: all constants match jda1.jda values ✅
- Stack overflow from deep recursion: frame depth ~5 levels, ~150–200 bytes per frame ✅
- loc_tbl overflow: parse_let has ~10 locals, LOC_TBL_CAP=65536 bytes ✅
- gen_expr clobbering r12/r13: gen_expr_base saves/restores both ✅
- Prototype handling: body_tok=0 check correctly skips prototypes ✅
- Fall-through into .gs_emit_mmap: preceded by `jmp .gs_done` ✅

### Leading suspect
`.ges_call` in jda0.asm uses r15 as a temp for `code_off` (`mov r15, [rax+40]`) while also
using r11 for the pre-resolved fn entry pointer.  If a call expression is emitted inside the
body of function 97 and something in the surrounding context placed cod_buf_ptr (0x20000000)
in r15 before gen_fn was invoked, the corrupted r15 could propagate into a stack write path
that overwrites the return address.  Alternatively, the _start emission push/pop sequence in
`p2_gen` or an unbalanced push/pop in `gen_addr`'s `.ga_index` section could shift the stack
such that a later `mov` or `call` clobbers [rbp+8].

🟡 Next work:
- instrument jda0 P2 gen_fn entry/exit with a canary check (write 0xDEADBEEF to [rbp+8] on
  entry, verify on exit) to confirm the return address is being overwritten inside gen_fn
- add `push r15` / `pop r15` to gen_fn prologue/epilogue (r15 not currently saved; may not fix
  the crash but will isolate whether r15 clobber is the vector)
- audit `.ges_call` to ensure cod_buf_ptr never aliases a general-purpose scratch register that
  could reach a stack write site
- once the overwrite path is identified and fixed, rebuild and verify:
  - `make stage1`  (jda0 → jda1_new) exits 0
  - `./jda1 ../stage1/jda1.jda jda1_sh2`  (jda1_new → jda1_sh2) exits 0
  - `./jda1_sh2 ../stage1/jda1.jda jda1_sh3`  exits 0, matches jda1_sh2 bytewise
- after jda0 is stable again, resume session-2 `print(integer)` / panic() fix for roundtrip

Latest checkpoint (2026-03-15, session 2):

✅ Done in session 2:
- fixed stage-1 `main()` stack overflow: `JirFunction{}` (6.3 MB) and `LowerCtx{}` (100 KB) were
  declared inside `loop more_top == 1`; jda0 allocates full `sizeof(struct)` on the frame per
  declaration, so each iteration grew the frame by ~6.4 MB — after ~46 functions the 524 MB ulimit
  was exceeded; fix: move both allocations outside the loop
- fixed argv clobber: diagnostic `print("M0\n")` was placed before `asm { out argv_ptr = rsi }`;
  jda0's `print` built-in uses `rsi` as the write-syscall buffer → clobbers the argv base from
  `_start`; fix: `asm { out argv_ptr = rsi }` and subsequent g_argv_base/g_src_path/g_out_path
  assignments must be the very first statements in `main()`, before any `print()` call
- removed all temporary diagnostic prints from stage-1 `main()` (M0/Ma/Mb/Mc/Md/Me/Mf/M1–M3)
- confirmed `jda1_new → jda1_sh2` exits 0, produces ~721 KB binary ✅
- added `OP_ARGV_BASE = 31` opcode: fixes argv capture in write_elf-compiled binaries (JMP-based
  `_start`); `compile_asm_argv_inline` detects `asm { out VAR = rsi }` and emits OP_ARGV_BASE
  which lowers to `lea rax, [rbp+16]; store` — correct for the JMP-to-main stack layout
- `jda1_sh2 → jda1_sh3` now produces output (721 KB binary, exits 0) ✅
- expanded token buffer: 65535 → 131071 (alloc_pages 512→1024, all overflow checks updated)
  — required because write_elf compiled binaries correctly lex jda1.jda's 44800 tokens

Session 2 blocker (superseded by jda0 P2 crash above):
- `print(integer)` causes OP_STRLEN segfault in write_elf-compiled binaries

Previous checkpoint (2026-03-14):

✅ Done in that cycle:
- replaced the old nondeterministic stage-1 crash with deterministic frontier tracking in Docker
- fixed bounds safety in lowering use tracking paths (`mark_use` / `consume_use` style guards and related flow)
- split `lower_fn(...)` into small helpers to remove its previous `emit slot overflow` blocker:
- `lower_fn_emit_prologue`
- `lower_fn_store_params`
- `lower_fn_collect_uses`
- `lower_fn_emit_blocks`
- `lower_fn_emit_epilogue`
- `lower_fn_patch_fixups`
- added targeted legacy skips for dead `live_codegen_*` helper cluster to avoid crashing in unused path compilation
- removed large non-functional debug print scaffolding from stage-1 `main()` hot path to reduce block pressure
- fixed top-level function table hard limit mismatch (`fi >= 256`) to match allocated `i64[512]` tables

Previous blocker (2026-03-14, now superseded):
- `jda1_a -> jda1_b` compile reached `F 254 main` and panicked (`pos=42116`) while compiling
  stage-1 `main()` itself → resolved by the stack-overflow + argv-clobber fixes above

1. Stage 0 bootstrap stability
Status: ✅ done

✅ Stage 0 fixes:
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

✅ Stage 1 fixes:
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
- extracted `lower_print_int(...)` out of `lower_instr(...)` to shrink the hottest late-lowering function without changing emitted behavior
- extracted `lower_syscall(...)` out of `lower_instr(...)` and kept the same syscall argument shuffle logic

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
- the top-level scanner now reliably reaches the real end of file (`... syscall(...)\n}`), so the earlier "premature EOF" suspicion was ruled out
- the current top-level frontier has moved past `emit_lea_rip(...)` into later helpers, and the latest runtime crash signal on `hello` points at the `live_codegen_primary_inline(...)` band
- the `lower_print_int(...)` extraction is a keeper: the high selfhost path now clears that helper and pushes through `lower_instr(...)` much more often
- the `lower_syscall(...)` extraction is also a keeper: the best current selfhost runs now clear `lower_instr(...)`, `lower_block(...)`, `lower_fn(...)`, `write_elf(...)`, `get_argv(...)`, and reach `main`
- the restored 5-run sample on the current kept baseline showed a spread of `111 / 85 / 26 / 213 / 67`, which confirms the build is still nondeterministic but the ceiling is now `main`
- stable early helper wrappers for `ok(...)`, `lookup_const(...)`, `print_span(...)`, `live_codegen_expr_inline(...)`, and `regalloc_free(...)` reduced unresolved helper calls from `178` to `0`
- fixing the `argv_ptr` bootstrap-let path restored real `main()` compilation:
- `PH mlet 86`
- `PH mpr 44`
- `PH mstr 412` to `428`
- removing dead default `OP_CONST` emission from skipped bootstrap lets moved runtime from `PH g0` to `PH argvs`

- make `jda1_a -> jda1_b` deterministic again before trusting any later `jda1_b -> hello` result

🟡 Concrete next edits:
- keep the current stage-0 global metadata fix unchanged
- keep the current skipped-function resync logic unchanged
- keep the current main-body probes until the post-`PH argvs` crash is localized
- narrow the next runtime window to the first statement after `PH argvs`
- verify whether the next bad step is:
- the first `print(...)` after `PH argvs`
- the first `syscall(1, 1, src_path, 1)`
- or the first `cstr_len(src_path)`
- keep debug probes minimal and targeted (only around the active crash window) to reduce clobber risk
- keep optimizer passes disabled until raw selfhost compilation is stable

🟡 Expected outcome of next fix:
- make `jda1_a -> jda1_b` complete reliably, not just intermittently
- then move `jda1_b -> hello.jda` past `PH argvs`
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
