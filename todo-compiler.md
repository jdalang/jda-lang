# Jda Stage 0 Compiler — Remaining TODO
docker run --rm --platform linux/amd64 -v $(pwd):/jda -w /jda/bootstrap/stage0 jda-dev make clean all test stage1

Bootstrap goal: `jda0` compiles `jda1.jda` → working `jda1` binary that can self-host.

## Current State
- All 88 functions in `jda1.jda` compile without crash ✓
- `jda1` binary starts, opens file, begins lexing — then segfaults
- Root cause: struct array field access (`arr[i].field`) is broken

---

## Bug Fixes Required

### 1. Fix `arr[i].field` struct array field read/write
**File:** `bootstrap/stage0/jda0.asm` — `gen_addr` / `.ga_index` + `.ga_dot`
**Symptom:** `buf[0].ttype` returns garbage stack address (~140737...) instead of stored value.
**Root cause:** TBD — `lv_esz` save/restore was applied but the wrong value is still returned. Likely the address emitted by `lea rax,[rbp-off]` + deref + scale + field offset is landing in the wrong place.
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

### 5. Fix `ptr[0] = val` deref-write (`out_cnt[0] = count`)
**File:** `gen_addr` / `.ga_index` + `gen_expr_stmt` / `.assign_lvalue`
**Symptom:** `jda1.jda`'s `lex()` ends with `out_cnt[0] = count` — writing through a pointer at index 0.
**Fix:** Verify `gen_addr` for `out_cnt[0]` correctly derefs the `&i64` pointer, scales by 8, and the store uses the right width (qword).

---

### 6. Fix top-level global `let` declarations
**File:** `p2_loop` / global variable handling
**Symptom:** `jda1.jda` has `let argv_ptr = 0` at top level (outside any function).
**Fix:** Ensure pass 2 main loop handles top-level `let` by adding to `glb_tbl` and emitting initialisation into the data/bss section rather than generating stack code.

---

### 7. Fix inline asm `asm { out argv_ptr = rsi }`
**File:** `gen_stmt` / `.gs_asm`
**Symptom:** `jda1.jda`'s `main()` uses `asm { out argv_ptr = rsi }` to capture the argv pointer passed in `rsi` at program entry.
**Fix:** Parse `out VARNAME = REGNAME`, emit `mov [rbp-off], rsi` (or appropriate register) for the named variable.

---

### 8. Fix struct literal init `let x = Struct{}`
**File:** `gen_stmt` / `.gs_let_struct`
**Symptom:** `jda1.jda` zero-inits large structs: `let ast = Node{}`, `let jfn = JirFunction{}`, `let ctx = LowerCtx{}`.
**Fix:** Confirm `gs_let_struct` allocates via `mmap` (already zeroed by Linux), stores pointer correctly, and the struct size computed in pass 1 is accurate for all nested structs.

---

### 9. Fix nested function call arguments (`ret ok(0)`, `emit_byte(..., rex_byte(...))`)
**File:** `gen_expr` / `.do_call` / `gen_expr_stmt` / `.ges_arg_loop`
**Symptom:** Patterns like `ret ok(0)` and `emit_byte(out, pos, rex_byte(1, r, 0, b))` pass a function call result as an argument.
**Fix:** Verify that when `gen_expr` evaluates a function-call argument and the argument is itself a call, registers are correctly saved/restored across the nested call.

---

### 10. Fix `jfn.src = src_buf` — struct pointer field write
**File:** `gen_expr_stmt` / `gen_addr` / `.ga_dot`
**Symptom:** `jda1.jda` does `jfn.src = src_buf` where `jfn` is a local pointer to a `JirFunction` struct.
**Fix:** `gen_expr_stmt` sees `jfn` (ident), then `.` → `assign_lvalue`. `gen_addr` must deref `jfn` (TK_PTR → `mov rax,[rax]`) then add `src` field offset. Verify lv_isptr/lv_sid/lv_esz are set correctly for the store.

---

## Final Gate

### 11. End-to-end bootstrap test
Run the full chain:
```
jda0 bootstrap/stage1/jda1.jda jda1_bin   # stage 0 compiles stage 1
jda1_bin test.jda test_out                  # stage 1 compiles a test program
./test_out                                  # test program runs correctly
```
**Expected:** `test.jda = fn main() { print(42) }` → prints `42`.

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

                                                                                                                          
⏺ Sure. Let me enumerate all remaining issues based on what we know:                                                        
                                                                                                                            
⏺ Here's the full TODO list:                                                                                                
                                                                                                                          
  ┌─────┬────────────────────────────────────────────────────────┬─────────────────┐                                        
  │  #  │                          Task                          │     Status      │                                      
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤                                        
  │ 32  │ Fix arr[i].field struct array field read/write         │ Current blocker │                                        
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤                                        
  │ 33  │ Fix let inside loop accumulating locals each iteration │ DONE            │ 
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤ 
  │ 34  │ Fix else if chain compilation                          │ DONE            │ 
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤ 
  │ 35  │ Fix compound or/and conditions                         │ DONE            │ 
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤ 
  │ 36  │ Fix ptr[0] = val deref-write                           │ Pending         │ 
                                        
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤                                        
  │ 37  │ Fix top-level global let                               │ Pending         │                                        
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤                                      
  │ 38  │ Fix inline asm asm { out var = reg }                   │ Pending         │                                        
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 39  │ Fix struct literal init let x = Struct{}               │ Pending         │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 40  │ Fix nested function call arguments                     │ Pending         │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 41  │ Fix jfn.src = val struct-pointer field write           │ Pending         │
  ├─────┼────────────────────────────────────────────────────────┼─────────────────┤
  │ 42  │ End-to-end jda1 bootstrap test                         │ Final gate      │
  └─────┴────────────────────────────────────────────────────────┴─────────────────┘

