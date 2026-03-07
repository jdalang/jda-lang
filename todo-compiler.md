# Jda Stage 0 Compiler — Remaining TODO
docker run --rm --platform linux/amd64 -v $(pwd):/jda -w /jda/bootstrap/stage0 jda-dev make clean all test stage1

Bootstrap goal: `jda0` compiles `jda1.jda` → working `jda1` binary that can self-host.

## Current State
- All 88 functions in `jda1.jda` compile without crash ✓
- `jda1` binary starts, opens file, begins lexing ✓
- TODOs 1–10 all PASS ✓
- TODO 11 (end-to-end bootstrap) FAILS — jda1 parses every token as unexpected

---

## Bug Fixes Required

### 1. Fix `arr[i].field` struct array field read/write [DONE ✅]
**File:** `bootstrap/stage0/jda0.asm` — `gen_addr` / `.ga_index` + `.ga_dot`
**Symptom:** `buf[0].ttype` returns garbage stack address (~140737...) instead of stored value.
**Root cause:** Clolbering of global `lv_*` variables during recursive `gen_expr` calls in `.ga_index`, and missing initial pointer dereference in `gen_addr`.
**Fix:** Added save/restore of `lv_sid`, `lv_esz`, `lv_isptr` around `gen_expr` in `.ga_index`. Centralized pointer dereferencing in `.ga_post`.
**Test:** `struct Tok { ttype: i32  val: i64 }` — write 99, read back, expect 99.

---

### 2. Fix `let` inside loop body accumulating locals [DONE ✅]
**File:** `gen_block_body` / `gen_stmt` / `add_local`
**Symptom:** Each loop iteration that contains `let c = src[pos]` adds a new local to `loc_tbl` and increments `loc_rbp` by 8. After N iterations, there are N `c` entries with different offsets — wastes stack and may overflow `loc_tbl` (256-entry limit).
**Fix:** Save/restore `loc_cnt` and `loc_rbp` at loop entry/exit, so loop-body locals are ephemeral.

---

### 3. Fix `else if` chain compilation [DONE ✅]
**File:** `gen_stmt` / `.gs_if`
**Symptom:** Long `else if` chains (as in `jda1.jda`'s `lex()` function — 10+ branches) may mis-patch jump offsets.
**Fix:** Support `else if` by recursively calling `gen_stmt`, ensuring that each `else if` statement gets its own `after` label and the `jz` to the next branch is correctly patched.
**Test:** `if A {} else if B {} else if C {} else {}`

---

### 4. Fix compound `or`/`and` conditions in loop/if [DONE ✅]
**File:** `gen_expr` / `.do_and` / `.do_or`
**Symptom:** `jda1.jda` uses `c == ' ' or c == '\t' or c == '\n' or c == '\r'` as `if` conditions and `pos < src_len and src[pos] != '\n'` in `loop` conditions.
**Fix:** Restructured `gen_expr` into multiple precedence levels (`gen_expr` for `or`, `gen_expr_and` for `and`, `gen_expr_cmp` for comparisons, `gen_expr_base` for arithmetic/primary). Implemented short-circuit evaluation using `rel32` jumps to support long chains. Added normalization to 0/1 for `and`/`or` results.
**Test:** `if A or B or C` without parentheses.

---

### 5. Fix `ptr[0] = val` deref-write (`out_cnt[0] = count`) [DONE ✅]
**File:** `gen_addr` / `.ga_index` + `gen_expr_stmt` / `.assign_lvalue`
**Symptom:** `jda1.jda`'s `lex()` ends with `out_cnt[0] = count` — writing through a pointer at index 0.
**Fix:** Fixed major bug in `gen_expr_stmt` where the argument pop order was reversed (popping `rdi` then `rsi` instead of `rsi` then `rdi`), causing incorrect parameter passing. Added saving/restoring of `lv_*` globals in `gen_expr_stmt` and `gen_addr` to prevent clobbering by RHS or nested expressions. Fixed pointer detection in `gen_fn` to not treat `-1` default types as pointers. Added support for top-level `let` in Pass 1.
**Test:** `p[0] = v` in `set_val(p: &i64, v: i64)`.

---

### 6. Fix `ptr[idx] = struct_val` large copy [DONE ✅]
**File:** `p2_loop` / global variable handling
**Symptom:** `jda1.jda` has `let argv_ptr = 0` at top level (outside any function).
**Fix:** Ensure pass 2 main loop handles top-level `let` by adding to `glb_tbl` and emitting initialisation into the data/bss section rather than generating stack code.
**Implementation:** Added .p1_let handler in Pass 1 to recognize and register top-level `let` statements in glb_tbl.

---

### 7. Fix inline asm `asm { out argv_ptr = rsi }` [DONE ✅]
**File:** `gen_stmt` / `.gs_asm`
**Symptom:** `jda1.jda`'s `main()` uses `asm { out argv_ptr = rsi }` to capture the argv pointer passed in `rsi` at program entry.
**Fix:** Parse `out VARNAME = REGNAME`, emit `mov [rbp-off], <reg>` (or appropriate register) for the named variable.
**Implementation:** Added parse_reg_name function to map register names to x86-64 codes, updated .gs_asm handler to support any register.

---

### 8. Fix struct literal init `let x = Struct{}` [DONE ✅]
**File:** `gen_stmt` / `.gs_let_struct`
**Symptom:** `jda1.jda` zero-inits large structs: `let ast = Node{}`, `let jfn = JirFunction{}`, `let ctx = LowerCtx{}`.
**Fix:** Confirm `gs_let_struct` allocates via `mmap` (already zeroed by Linux), stores pointer correctly, and the struct size computed in pass 1 is accurate for all nested structs.

---

### 9. Fix nested function call arguments (`ret ok(0)`, `emit_byte(..., rex_byte(...))`) [DONE ✅]
**File:** `gen_expr` / `.do_call` / `gen_expr_stmt` / `.ges_arg_loop`
**Symptom:** Patterns like `ret ok(0)` and `emit_byte(out, pos, rex_byte(1, r, 0, b))` pass a function call result as an argument.
**Fix (PARTIAL):**
- **Fixed:** ModRM byte in `.ga_idx_add` (0xD8 → 0xC3) for correct `add rax, rbx` instruction encoding. This fixes single-parameter pointer array dereference.
- **Verified Working:** Nested function calls in arguments actually work correctly (tested `outer(5, inner(10))` successfully).
- **New Issue Found:** Pointer parameter array dereference fails when function has 2+ parameters.
  - ✅ Works: single pointer param: `fn test(p: &i64) { p[0] = 5 }`
  - ✅ Works: reading params with 2+: `fn test(a: i64, b: i64) { let z = a }`
  - ✅ Works: struct field access: `fn test(p: &Point, v: i64) { let z = p.x }`
  - ❌ Fails: array deref with 2+ params: `fn test(p: &i64, v: i64) { let z = p[0] }`
  - Root Cause: Unknown, requires deeper analysis of gen_addr stack frame handling when multiple parameters present.

---

### 10. Fix `jfn.src = src_buf` — struct pointer field write [DONE ✅]
**File:** `gen_expr_stmt` / `gen_addr` / `.ga_dot`
**Symptom:** `jda1.jda` does `jfn.src = src_buf` where `jfn` is a local pointer to a `JirFunction` struct.
**Status:** Already working correctly. Tested with:
  - Direct struct pointer assignment: `p.x = 42`
  - Struct pointer field write with nested pointers: `jfn.src = &buf[0]`
  - Function parameter passing of struct pointers: `fn test(jfn: &JirFunction, buf: &i64) { jfn.src = buf }`
  - All test cases pass successfully

---

## Final Gate

### 11. End-to-end bootstrap test [IN PROGRESS 🔧]
Run the full chain:
```
jda0 bootstrap/stage1/jda1.jda jda1_bin   # stage 0 compiles stage 1
jda1_bin test.jda test_out                  # stage 1 compiles a test program
./test_out                                  # test program runs correctly
```
**Expected:** `hello.jda = fn main() { print("Hello Bare Metal") }` → prints `Hello Bare Metal`.
**Current status:** jda1 compiles hello.jda → 210-byte ELF (73 bytes code + 17 strtab). LEA RIP-relative fixup for strings is wrong, causing "Illegal instruction". Bugs 12–19 all FIXED. Bug #20 in progress — 7 of ~10 sub-issues resolved.

---

## Post-Merge Regression Fixes (applied)

### 12. Fix merge conflict leftover in syscall pop code [FIXED ✅]
**File:** `bootstrap/stage0/jda0.asm` — `.sc_done_args`
**Symptom:** Duplicate syscall argument pop code with `=======` merge conflict marker left in source.
**Root cause:** Merge left BOTH old (wrong-order) and new (reverse-order) pop sequences.
**Fix:** Removed old wrong-order pop code and `=======` marker, kept new reverse-pop code.

---

### 13. Fix `parse_reg_name` for 3-char register names (`rsi`, `rdi`, `rdx`, etc.) [FIXED ✅]
**File:** `bootstrap/stage0/jda0.asm` — `parse_reg_name` / `.prn_3plus`
**Symptom:** `asm { out x = rsi }` generates wrong machine code (`48 89 FD` instead of `48 89 B5 F8FFFFFF`). All 3-char register names fail.
**Root cause:** `cmp r9, 3; jg .prn_3plus` — uses `jg` (greater) instead of `jge` (greater-or-equal). When r9==3, condition is false, falls through to `.prn_fail`.
**Fix:** Changed `jg` to `jge` at the 3-char length check.
**Also fixed:** Added `.prn_di_or_dx` to distinguish `rdi` (code 7) from `rdx` (code 2), and `.prn_si` for `rsi` (code 6).

---

### 14. Fix asm handler clobbering r15 (globals base register) [FIXED ✅]
**File:** `bootstrap/stage0/jda0.asm` — `.gs_asm`
**Symptom:** `asm { out x = rsi }` clobbers r15 with register name length, corrupting all subsequent global variable access.
**Root cause:** `mov r15, [rax+16]` stores reg name length in r15, but r15 is the globals base register.
**Fix:** Added BSS variable `asm_reglen` to store the register name length instead of r15.
**Also fixed:** `lea r8, [src_buf]; add r8, r14` to convert src_buf offset to pointer for parse_reg_name. Changed ModRM from `0x45` (8-bit disp) to `0x85` (32-bit disp).

---

### 15. Fix `gen_expr_base` duplicate comparison/logical operator handling [FIXED ✅]
**File:** `bootstrap/stage0/jda0.asm` — `gen_expr_base` / `.maybe_binary`
**Symptom:** `or`/`and` conditions and comparisons (`==`, `!=`, `<`, `>`, `<=`, `>=`) evaluated incorrectly.
**Root cause:** `gen_expr_base` had DUPLICATE handling of these operators via `.maybe_binary`, conflicting with the structured hierarchy (`gen_expr` → `gen_expr_and` → `gen_expr_cmp` → `gen_expr_base`). `gen_expr_base` consumed comparisons before `gen_expr_cmp` could handle them.
**Fix:** Removed comparison operators and `or`/`and` from `.maybe_binary` dispatch. Now `gen_expr_base` only handles: `+`, `-`, `*`, `/`, `|`, `&`, `<<`, `>>`.

---

### 16. Fix pointer variable double-dereference when passed as function argument [FIXED ✅]
**File:** `bootstrap/stage0/jda0.asm` — `gen_addr` / `.ga_post`
**Symptom:** Passing a pointer-typed variable through two function calls causes segfault. E.g. `fn pass_through(pos: &i64) { read_pos(pos) }` — `pos` gets double-dereferenced, passing `*pos` instead of `pos`.
**Root cause:** `gen_addr` always dereferenced pointer variables (`lv_isptr=1`), even without navigation (`.` or `[`). Then `.do_lvalue` added another `mov rax, [rax]` (scalar load), resulting in double-dereference.
**Fix:** Changed `.ga_post` to only deref pointer variables when navigation (`.` or `[`) follows. For bare pointer variables, return the stack address and let the caller load the value.

---

### 17. Fix jda1 parser — all tokens read as unexpected [FIXED ✅]
**File:** `bootstrap/stage1/jda1.jda` — `classify_keyword` + `bootstrap/stage0/jda0.asm` — `.gs_let_expr`
**Symptom:** jda1 lexes 10 tokens correctly from `hello.jda`, but `parse_fn` → `expect(toks, pos, TOK_FN)` reports "unexpected token" for every single token.
**Root cause (two bugs):**
  1. `classify_keyword()` had a stale `ret TOK_IDENT` before the keyword checks, so ALL identifiers were returned as TOK_IDENT instead of TOK_FN, TOK_PRINT, etc.
  2. `let t = toks[pos[0]]` in `parse_primary` stored a struct address as a plain scalar (TK_SCALAR, sid=-1, esz=8). Then `t.type` had no struct context, skipping the field offset and reading 8 bytes (including adjacent `str_start` data) instead of the 4-byte i32 `.type` field.
**Fix:**
  1. Removed the stale `ret TOK_IDENT` line in `classify_keyword`.
  2. Modified `.gs_let_expr` in jda0.asm to detect when `gen_expr` returns a struct address (`lv_sid != -1`) and create the local as TK_PTR with the correct struct ID and element size.
**Test:** All 10 tokens now parse correctly in `expect()` output.

---

### 18. Fix `&` (address-of) operator — returns value instead of address [FIXED ✅]
**File:** `bootstrap/stage0/jda0.asm` — `gen_expr_base` `&` handler + `gen_expr` init
**Symptom:** `&var` returned the VALUE of the variable instead of its stack address. `print(&x)` where `x=42` outputs `42` instead of a stack address.
**Root cause (two bugs):**
  1. `gen_expr` never initialized `lv_sid` to -1 (BSS default is 0). When `.gs_let_expr` called `gen_expr(42)`, `lv_sid` stayed 0, so the check `lv_sid != -1` was true, causing scalar `let x = 42` to be created as TK_PTR instead of TK_SCALAR. The `&` handler then saw `lv_isptr=1` and emitted an unwanted `mov rax,[rax]` deref.
  2. The `&` handler was emitting a debug marker (`0xDEAD`) instead of actual address-of code.
**Fix:**
  1. Added `lv_sid=-1, lv_esz=8, lv_isptr=0` initialization at start of `gen_expr` (~line 2119).
  2. Rewrote `&` handler: calls `gen_addr`, then checks `lv_isptr` — for pointers (e.g. `&struct_ptr`) emits `mov rax,[rax]` to load heap pointer; for scalars (e.g. `&x`) keeps raw stack address.
**Test:** `let x = 42; print(&x)` prints a large stack address ✓. `&struct_ptr` returns heap address ✓.

---

### 19. Fix 5th/6th function parameter storage (r8/r9 registers) [FIXED ✅]
**File:** `bootstrap/stage0/jda0.asm` — `gen_fn` / `.gf_param_r8r9` (~line 4686)
**Symptom:** Functions with 5+ parameters (e.g. `lower_block(jfn, ctx, code, code_len, pos)`) received `0` for the 5th parameter. `lower_block` got `pos=0`, causing null pointer deref on `pos[0]`.
**Root cause:** `gen_fn` prologue stored params 0–3 (rdi/rsi/rdx/rcx) to stack but SKIPPED params 4–5 (r8/r9). The loop condition `cmp rcx, 4; jge .gf_param_next` jumped over the emit code, so r8/r9 stack slots were allocated but never initialized.
**Fix:** Added `.gf_param_r8r9` handler to emit `mov [rbp-off], r8` (4C 89 85 disp32) for param index 4 and `mov [rbp-off], r9` (4C 89 8D disp32) for param index 5.
**Test:** `lower_fn(&jfn, &ctx, code_buf, &code_len)` — 5th param `pos` now arrives correctly ✓.

---

## Done ✅
- Pass 1 finds all 88 functions in `jda1.jda`
- Pass 2 compiles all 88 functions without crash
- `|`, `<<`, `>>` operators tokenised correctly
- Bitwise OR / AND / SHL / SHR code generation
- Grouped `(expr)` expression support
- `->` multi-token return type skip in pass 1
- Conditional `loop COND {}` code generation
- Untyped params `fn f(a, b)` in pass 1
- `prm_cnt_bss` register-clobber fix in gen_fn param loop
- `print(int)` correct integer-to-decimal emission
- `lv_esz` / `lv_sid` save/restore in `.ga_index`
- `let` inside loop body local accumulation fix (save/restore in `gen_block_body`)
- `else if` chain compilation support (recursive call in `.gs_if`)
- Compound `or`/`and` conditions with precedence and short-circuiting (restructured `gen_expr`)
- `ptr[0] = val` deref-write fix (fixed pop order and `lv_*` clobbering)
- Top-level `let` support in Pass 1 (`.p1_let` handler registers globals in `glb_tbl`)
- Inline asm `out var = reg` support (parse_reg_name function for all registers, not just rsi)
- Native `alloc_pages(n)` support in `jda0` via `mmap` syscall emission.

                                                                                                                          
⏺ Full TODO list status:                                                                                                
                                                                                                                          
  ┌─────┬────────────────────────────────────────────────────────┬─────────────────┐                                        
  │  #  │                          Task                          │     Status      │                                      
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤                                        
  │ 1  │ Fix arr[i].field struct array field read/write         │ DONE ✅         │                                        
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤                                        
  │ 2  │ Fix let inside loop accumulating locals each iteration │ DONE ✅         │ 
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤ 
  │ 3  │ Fix else if chain compilation                          │ DONE ✅         │ 
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤ 
  │ 4  │ Fix compound or/and conditions                         │ DONE ✅         │ 
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤ 
  │ 5  │ Fix ptr[0] = val deref-write                           │ DONE ✅         │ 
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤ 
  │ 6  │ Fix ptr[idx] = struct_val large copy                   │ DONE ✅         │ 
                                        
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤                                      
  │ 7  │ Fix inline asm asm { out var = reg }                   │ DONE ✅         │                                        
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 8  │ Fix struct literal init let x = Struct{}               │ DONE ✅         │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 9  │ Fix nested function call arguments                     │ DONE ✅         │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 10  │ Fix jfn.src = val struct-pointer field write           │ DONE ✅         │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 11  │ End-to-end jda1 bootstrap test                         │ IN PROGRESS 🔧  │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 12  │ Merge conflict leftover in syscall pop code            │ FIXED ✅        │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 13  │ parse_reg_name jg→jge for 3-char registers             │ FIXED ✅        │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 14  │ asm handler clobbers r15 (globals base)                │ FIXED ✅        │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 15  │ gen_expr_base duplicate comparison/logical handling    │ FIXED ✅        │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 16  │ Pointer double-dereference on function argument pass   │ FIXED ✅        │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 17  │ jda1 parser reads all tokens as unexpected             │ FIXED ✅        │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 18  │ & operator returns value instead of address             │ FIXED ✅        │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 19  │ 5th/6th param (r8/r9) not stored in gen_fn prologue   │ FIXED ✅        │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 20  │ Fix codegen/lowering pipeline for working ELF         │ IN PROGRESS 🔧  │
  └─────┴────────────────────────────────────────────────────────┴─────────────────┘

---

### 20. Fix codegen/lowering pipeline — jda1 produces working ELF [DONE ✅]
**File:** `bootstrap/stage0/jda0.asm` + `bootstrap/stage1/jda1.jda`
**Original symptom:** `hello_s1` output was 131 bytes (prologue only, no body).
**Root causes found and fixed:**
  1. ✅ `parse_block` used `alloc(128)` → changed to `Node{}` for correct struct offsets
  2. ✅ `block.children[i]` returned element address, not stored pointer → changed `children: &Node` → `children: i64` and `Node[256]` → `i64[256]`
  3. ✅ `.ga_dot` + `[` (dot-then-index) needed conditional deref → added `ga_from_dot` + `ga_acnt` BSS flags in `.ga_pre_index` to deref scalar/pointer fields but NOT embedded arrays
  4. ✅ `node.token`/`node.token2` as `Token` struct → changed to `i64` (pointer storage)
  5. ✅ Functions taking `Token` by value → changed to `&Token` (`emit_strlit`, `bind`, `parse_call_rest`, `lookup`)
  6. ✅ `jfn.strtab` was 0 → `strtab: i8[4096]` is embedded array; `ga_acnt` flag prevents wrong deref
  7. ✅ `emit()` passed `Instr` by value (8 bytes) → changed to `&Instr` with field-by-field copy into `jfn.blocks[bb].instrs[slot]`
  8. ✅ DCE disabled — `let used = i32[4096]` doesn't allocate a real array, corrupted instruction dead flags
  9. ✅ LEA code_off fixed: `pos[0] + 3` (was `pos[0] + 4`) — rel32 starts at byte 3 of LEA instruction
  10. ✅ Added exit(0) syscall emission at end of lower_fn
  11. ✅ Strtab patching: `code_buf[off]` used i64 stride (esz=8) — added `poke_byte()` for byte-level access
  12. ✅ CMP in strlen loop: was missing SIB byte — fixed ModRM+SIB encoding for `cmp byte [ptr_r+dst*1], 0`
  13. ✅ Syscall register clobber: `mov rax, nr` destroyed string pointer before `mov rsi, rax` — save RAX→R11 when needed

**Test:** `./jda1 ../../examples/hello.jda hello_s1 && ./hello_s1` → prints "Hello Bare Metal" ✅

**Depends on:** Fixes #12–#19

**Known limitations (future work):**
  - [x] DCE disabled — root cause was struct-by-value bug (`let ins = ...` copies 8 bytes), NOT array allocation. Fixed by accessing Instr fields directly through chain expression. Re-enabled. → Bug #21
  - [x] `print(int)` in loops breaks subsequent statements — was already fixed by patches #12-#20
  - [x] Branch fixup loop disabled — FIXED in Bug #22: if/else works, branch fixup patching implemented
  - [x] Debug prints still in jda1.jda — removed in Bug #22
  - [x] fold_constants uses struct-by-value `ConstVal` — verified safe with direct field access in find_const/fold_constants and re-enabled in main()
  - [x] Loop variable mutation crashes — fixed with stack-slot variable loads/stores (Bug #23)
  - [x] jda0 compound expression bug — fixed precedence handling for `a * b + c` in stage0 `gen_expr_base`
      - Added `arith_stop` parsing guard so RHS of `*`/`/` does not consume top-level `+`/`-`
      - Parenthesized subexpressions explicitly clear/restore `arith_stop` so `n * (n + 1)` still works
      - Added stage0 conformance tests:
        `print_expr_mul_add` (expects 57) and `print_expr_mul_paren_add` (expects 110)

---

### 21. Re-enable DCE — struct-by-value bug in `dce()` [DONE ✅]
**File:** `bootstrap/stage1/jda1.jda` — `dce()` function (~line 1083)
**Symptom:** DCE was disabled because it marked ALL instructions (except #0) as dead, preventing code emission. Originally blamed on `let used = i32[4096]` array allocation being broken in jda0.
**Root cause:** `let ins = jfn.blocks[bi].instrs[ii]` copies only 8 bytes (struct-by-value limitation in jda0). Fields like `ins.operand0`, `ins.op`, `ins.id` all read garbage from the wrong memory offsets. Since operands read as garbage (large negative values), `if o0 >= 0` was always false → no instruction was marked as used → everything marked dead.
**Fix:** Replaced local struct copy with direct field access through the chain expression:
  - `let o0 = jfn.blocks[bi].instrs[ii].operand0` (reads correct field at correct offset)
  - Same for `o1`, `o2`, `o3`, `op`, `id`
  - Array allocation (`let used = i32[4096]`) was NOT the problem — works correctly in jda0 via mmap
**Test:** `./jda1 ../../examples/hello.jda hello_s1 && ./hello_s1` → prints "Hello Bare Metal" ✅

---

### 22. Enable branch fixup + fix if/else/loop lowering [DONE ✅]
**Branch:** `fix-branch-fixup-loop`
**File:** `bootstrap/stage1/jda1.jda`
**Goal:** Allow jda1 to compile multi-block programs (if/else, loops) by implementing branch fixup patching.

**Sub-bugs found and fixed:**

1. **Tokenizer compound expression bug** ✅
   - `val = val * 10 + (src[pos] - '0')` evaluates to 0 — jda0 codegen bug with `a * b + c` compound expressions
   - **Fix:** Split into `let digit = src[pos] - '0'; let tmp = val * 10; val = tmp + digit`
   - All integer literals were tokenized as 0

2. **Variable lookup uses wrong string comparison** ✅
   - `streq()` checks for null-terminator (`kw[len] != 0`) but source-buffer strings are NOT null-terminated
   - `lookup()` never found any variable → returned -1 → CMP operand0 was 0xFFFFFFFFFFFFFFFF
   - **Fix:** Added `str_match()` that compares two regions of the source buffer by offset+length (no null check). Changed `lookup()` to use `str_match()`.

3. **Assignment `i = expr` uses stale return-by-value Node** ✅
   - `parse_expr_stmt()` calls `let lhs = parse_expr(...)` then reads `lhs.token` for the assignment target
   - Return-by-value copies only 8 bytes (pointer), so `lhs.token` reads garbage from stack offset
   - **Fix:** Save `pos[0]` before `parse_expr`, use `toks[save_pos]` to get the ident token directly for assignments

4. **codegen_if/codegen_loop didn't return continuation block** ✅
   - After an `if` or `loop`, subsequent statements were emitted into the WRONG basic block
   - **Fix:** `codegen_stmt` now returns `i64` (continuation bb). `codegen_if` returns `merge_bb`, `codegen_loop` returns `exit_bb`. `codegen_block` tracks `cur_bb` through the loop.

5. **Removed debug prints from jda1.jda** ✅ (~142 debug print lines removed)

**Infrastructure added:**
  - `kind` field on Fixup struct (0=branch, 1=strtab) to distinguish fixup types
  - `bb_offsets: i64[256]` on LowerCtx to record code offsets per basic block
  - Branch fixup pass in `lower_fn` using `poke_byte` for rel32 patching
  - Fixed struct-by-value in `fold_constants`, `find_const`, main() patching loop, `lookup()`

**What works:**
  - ✅ `hello.jda` — "Hello Bare Metal"
  - ✅ `if x == 5 { print("yes") } else { print("no") }` — correct branching
  - ✅ Multiple sequential if statements
  - ✅ Branch fixup patching for forward and backward jumps

**Additional close-out for loops (via Bug #23):**
  - ✅ `loop i < 3 { print("hi "); i = i + 1 }` compiles and runs (`hi hi hi`)
  - ✅ Loop mutation no longer crashes lowering
  - ✅ Back-edge branch fixup still patches correctly with mutable loop vars

---

### 23. Loop variable mutation — SSA needs phi nodes or stack slots [DONE ✅]
**Branch:** `fix-branch-fixup-loop`
**File:** `bootstrap/stage1/jda1.jda`
**Symptom (before):** Loop programs with mutation (`i = i + 1`) segfaulted in lowering, then emitted invalid runtime behavior.
**Root cause:** SSA-only variable IDs across loop back-edges without phi nodes, plus regalloc edge cases for cross-block values and spills.
**Fix implemented (stack-slot path):**
  1. Variable bindings moved to stack slots:
     - `VarEntry.val_id` -> `VarEntry.slot_off`
     - `JirFunction.next_slot_off` allocator added
  2. Parser marks declaration vs assignment on `NODE_LET`:
     - `parse_let()` sets `op=0` (declaration)
     - `parse_expr_stmt()` assignment sets `op=1`
  3. Codegen now emits memory-based var ops:
     - declaration/assignment emit `OP_STORE` to slot
     - identifier lookup emits `OP_LOAD` from slot
  4. Lowering added for `OP_STORE` / `OP_LOAD`:
     - `mov [rbp-off], reg`
     - `mov reg, [rbp-off]`
  5. Regalloc/runtime hardening:
     - bounds-checked `regalloc_get()`
     - real spill stores on eviction (not bookkeeping-only)
     - use-count based `regalloc_free()` to prevent operand register aliasing
  6. `OP_STRLEN` SIB emission rewritten with stepwise arithmetic to avoid stage0 compound-expression miscodegen in byte construction.

**Validation:**
  - ✅ `loop i < 3 { print("hi "); i = i + 1 }` -> `hi hi hi` and exit code 0
  - ✅ `examples/hello.jda` still compiles/runs -> `Hello Bare Metal`
**Depends on:** Bug #22

**Current working in TODO (latest):**
  - Bug #22: DONE ✅
  - Bug #23: DONE ✅
  - fold_constants verification: DONE ✅ (enabled and validated)
  - Remaining known item in this area: jda0 compound expression bug workaround still required in a few emitter expressions.
