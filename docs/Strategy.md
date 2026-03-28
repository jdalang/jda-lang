Strategy

Latest checkpoint (2026-03-22):

Pipeline

- ✅ documented template-backed gate still passes in Docker:
- ✅ `./jda1 ../stage1/jda1.jda /tmp/jda1_sh2`
- ✅ `/tmp/jda1_sh2 ../../examples/hello.jda /tmp/hello_sh2 && /tmp/hello_sh2`
- ✅ output is `Hello Bare Metal`
- ✅ hidden-template `jda0 -> jda1_a`
- ✅ hidden-template `jda1_a -> jda1_b` (943037 bytes, up from 514609 with struct fix)
- 🟡 hidden-template `jda1_b -> jda1_sh2` (jda1_b exits early in run_top_const_prelude)

Recent done

- ✅ identified root cause of wrong field codegen: `run_top_struct_prelude` was never called in main()
  so `g_stab_ptr` remained empty (cnt=0, field_cnt=0); all struct field reads returned base pointer
- ✅ added `run_top_const_prelude` and `run_top_struct_prelude` calls to main() after `init_large_post_lex_state()`
- ✅ jda1_b now builds at 943037 bytes (was 514609 before StructTable fix)
- ✅ jda1_b passes through IL0-IL3 (init_large_post_lex_state), enters run_top_const_prelude
- ✅ parse_const_decl advances pos correctly (TC_STUCK probe never fires)
- ✅ lower_fn_store_params pcnt fix: hardcoded word offset 1575432 for param_cnt read

Current behavior

- ✅ template-backed checkpoint remains green
- ✅ jda0 -> jda1_a -> jda1_b pipeline rebuilds cleanly
- 🟡 jda1_b prints: SRC=, OUT=, LGA, IL0-IL3, LGB, TC0 (g_runtime_src_len<1024), TCL0, TCI x3
- 🟡 jda1_b exits with code 0 after TCI x3 without printing LGC (after run_top_const_prelude)
  meaning run_top_const_prelude never returns to caller (exits or corrupts return address)

Current blocker

- 🟡 jda1_b exits cleanly inside run_top_const_prelude after ~3 const parse iterations
  - TC1 (end-of-function probe) is never printed
  - LGC (probe right after the call in main) is never printed
  - EXIT:0 rules out segfault (would be 139)
  - Likely cause: stack frame corruption or wrong return-address epilogue in jda1_b's
    compiled code for run_top_const_prelude; jda1_a compiled this function with the
    new StructTable but something in the frame/spill layout is wrong
- 🟡 g_runtime_src_len < 1024 (TC0 fires) even though jda1.jda is ~260KB
  - `g_runtime_src_len = src_len` in main() may be compiled to wrong global offset

This session

- ✅ identified root cause: `run_top_struct_prelude` never called in main() → empty StructTable
- ✅ identified mechanism: `live_codegen_postfix_inline` returns base pointer for all struct
  field reads when StructTable is empty → jfn.param_cnt returned jfn heap address → SIGSEGV
- ✅ added prelude calls to main() (lines after init_large_post_lex_state)
- ✅ added fine-grained probes: IL1A-IL1D, IL2A-IL2C (init_large_post_lex_state), TCL0/TCI/TC_STUCK
- ✅ confirmed IL2A-IL2C execute (g_stab_ptr struct field stores work in jda1_b)
- ✅ confirmed parse_const_decl advances pos (no TC_STUCK)
- 🟡 run_top_const_prelude does not return after loop completes (no TC1 or LGC printed)

Next work

- 🟡 diagnose why run_top_const_prelude exits the process instead of returning
  - add probe at very end of loop body and right before `ret ok(0)` at line 1996
  - check if the `if g_runtime_src_len < 1024 { print("TC1\n") }` at line 1996 ever fires
  - if it doesn't fire: the loop runs until process exits via corrupted return address
  - possible fix: simplify run_top_const_prelude by removing g_loop_ctrl and using a direct loop
- 🟡 investigate g_runtime_src_len being 0 despite src_len = ~260KB
  - add probe `print("SL=...") after g_runtime_src_len = src_len in main()
  - if it IS set correctly, the TC0 comparison may have an off-by-one or sign issue
- 🟡 once jda1_b produces jda1_sh2, verify it compiles hello.jda → `Hello Bare Metal`
- 🟡 keep the documented template-backed gate green after every change

Final testing

- ✅ documented Docker/Linux checkpoint passes:

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

- ⏳ real no-template completion is still pending:

Step 1:
```sh
nasm -f elf64 jda0.asm -o /tmp/jda0.o && ld /tmp/jda0.o -o /tmp/jda0
/tmp/jda0 ../stage1/jda1.jda /tmp/jda1_a
/tmp/jda1_a ../stage1/jda1.jda /tmp/jda1_b
```

Step 2:
```sh
/tmp/jda1_b ../stage1/jda1.jda /tmp/jda1_sh2
```

Step 3:
```sh
/tmp/jda1_sh2 ../../examples/hello.jda /tmp/hello_sh3 && /tmp/hello_sh3
```

Expected output:
```text
Hello Bare Metal
```

Files currently involved

- `bootstrap/stage0/jda1`
- `bootstrap/stage1/jda1.jda`
- `bootstrap/stage1/jda1_sh2_fast.bin`
- `bootstrap/stage1/hello_fast.bin`
- `bootstrap/stage1/exit_fast.bin`
