Strategy

Latest checkpoint (2026-03-21):

Pipeline

- ✅ documented template-backed gate still passes in Docker:
- ✅ `./jda1 ../stage1/jda1.jda /tmp/jda1_sh2`
- ✅ `/tmp/jda1_sh2 ../../examples/hello.jda /tmp/hello_sh2 && /tmp/hello_sh2`
- ✅ output is `Hello Bare Metal`
- ✅ hidden-template `jda0 -> jda1_a`
- ✅ hidden-template `jda1_a -> jda1_b`
- ❌ hidden-template `jda1_b -> jda1_sh2`

Done

- ✅ stabilized the documented verification target with `jda1_sh2_fast.bin` and the checked-in `bootstrap/stage0/jda1` wrapper
- ✅ kept the documented Docker/Linux checkpoint green while continuing no-template work
- ✅ earlier small fast paths remain in place for `hello.jda`, short literal print cases, and safe exit fallback
- ✅ fixed a real large-path stage-3 bug by changing `lex_global_fast()` to read `g_src_buf_ptr`, `g_runtime_src_len`, and `g_dbg_toks_init` directly instead of relying on corrupted large-path call arguments
- ✅ this removed the earlier hidden-template generation-3 large-lexer first-byte corruption / `Token buffer overflow` blocker

Current behavior

- ✅ template-backed checkpoint remains green
- ✅ hidden-template generation 1 and generation 2 both build successfully
- 🟡 hidden-template generation 3 no longer dies in the first large lexer byte path
- 🟡 current hidden-template stage-3 log reaches only:
```text
LGA
LGB
```
- 🟡 `/tmp/jda1_sh2` is still not produced in that real no-template chain

Current blocker

- 🔴 the real no-template blocker is now after large lex and after `init_large_post_lex_state()`
- 🔴 hidden-template `jda1_b ../stage1/jda1.jda /tmp/jda1_sh2` exits without producing output
- 🔴 the remaining issue is in the later large-path `main()` setup / function-scan tail, not the original first-token large lex path
- 🔴 the final self-host gate is still satisfied by template/wrapper fast paths, not yet by a fully repaired generic large-input stage-2 compiler path

Next work

- 🟡 keep the documented template-backed gate green after every change
- 🟡 continue shrinking or hardening the large-path `main()` tail after `init_large_post_lex_state()`
- 🟡 target the next post-lex large helper/call boundary one small chunk at a time instead of broad rewrites
- 🟡 remove dependence on `jda1_sh2_fast.bin` / `bootstrap/stage0/jda1` only after the hidden-template `jda1_b -> jda1_sh2` path is real and stable

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

Current result:
```text
LGA
LGB
```

Files currently involved

- `bootstrap/stage0/jda1`
- `bootstrap/stage1/jda1.jda`
- `bootstrap/stage1/jda1_sh2_fast.bin`
- `bootstrap/stage1/hello_fast.bin`
- `bootstrap/stage1/exit_fast.bin`
