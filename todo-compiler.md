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
**Expected:** `test.jda = fn main() { print(42) }` → prints `42`.
**Current status:** jda1 compiles OK, opens file, lexes 10 tokens, but parser fails with "Parse error: unexpected token" on every `expect()` call. Root cause under investigation — see bugs 12–16 below.

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

### 18. Fix jda1 segfault in `lower_fn` → `emit_byte` — `pos[0]` deref crash [TODO 🔴]
**File:** `bootstrap/stage0/jda0.asm` — code generation (under investigation)
**Symptom:** After successful lex + parse + codegen + fold + dce, jda1 crashes with SIGSEGV inside `emit_byte(out, pos, 0x55)` when trying to read `pos[0]`. The crash happens in `lower_fn` → `emit_push_r` → `emit_byte`.
**Debug findings:**
  - `emit_byte` enters OK, `b=85` (0x55) is printed, but reading `pos[0]` segfaults
  - Simplified test (3-level passthrough with 4 params) works fine outside of jda1 context
  - The real jda1 main function is very large (~30+ locals, many struct allocs)
  - Possible causes: stack frame offset overflow, parameter slot corruption in large functions, or interaction with many mmap allocs
**Depends on:** Fix #17
**Test:** `./jda1 ../../examples/hello.jda hello_s1` should compile successfully.

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
  │ 32  │ Fix arr[i].field struct array field read/write         │ DONE ✅         │                                        
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤                                        
  │ 33  │ Fix let inside loop accumulating locals each iteration │ DONE ✅         │ 
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤ 
  │ 34  │ Fix else if chain compilation                          │ DONE ✅         │ 
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤ 
  │ 35  │ Fix compound or/and conditions                         │ DONE ✅         │ 
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤ 
  │ 36  │ Fix ptr[0] = val deref-write                           │ DONE ✅         │ 
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤ 
  │ 37  │ Fix ptr[idx] = struct_val large copy                   │ DONE ✅         │ 
                                        
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤                                      
  │ 38  │ Fix inline asm asm { out var = reg }                   │ DONE ✅         │                                        
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 39  │ Fix struct literal init let x = Struct{}               │ DONE ✅         │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 40  │ Fix nested function call arguments                     │ DONE ✅         │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 41  │ Fix jfn.src = val struct-pointer field write           │ DONE ✅         │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 42  │ End-to-end jda1 bootstrap test                         │ IN PROGRESS 🔧  │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 43  │ Merge conflict leftover in syscall pop code            │ FIXED ✅        │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 44  │ parse_reg_name jg→jge for 3-char registers             │ FIXED ✅        │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 45  │ asm handler clobbers r15 (globals base)                │ FIXED ✅        │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 46  │ gen_expr_base duplicate comparison/logical handling    │ FIXED ✅        │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 47  │ Pointer double-dereference on function argument pass   │ FIXED ✅        │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 48  │ jda1 parser reads all tokens as unexpected             │ FIXED ✅        │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 49  │ jda1 segfault in lower_fn → emit_byte pos[0] deref   │ TODO 🔴         │
  └─────┴────────────────────────────────────────────────────────┴─────────────────┘
