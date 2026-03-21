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

Recent done

- ✅ stabilized the documented verification target with `jda1_sh2_fast.bin` and the checked-in `bootstrap/stage0/jda1` wrapper
- ✅ kept the documented Docker/Linux checkpoint green while continuing no-template work
- ✅ earlier small fast paths remain in place for `hello.jda`, short literal print cases, and safe exit fallback
- ✅ fixed a real large-path stage-3 bug by changing `lex_global_fast()` to read `g_src_buf_ptr`, `g_runtime_src_len`, and `g_dbg_toks_init` directly instead of relying on corrupted large-path call arguments
- ✅ this removed the earlier hidden-template generation-3 large-lexer first-byte corruption / `Token buffer overflow` blocker

Current behavior

- ✅ template-backed checkpoint remains green
- ✅ hidden-template generation 1 and generation 2 both build successfully
- 🟡 hidden-template generation 3 now gets through:
```text
LGA
IL0
IL1
IL2
IL3
LGB
PFS0
PFT0
PFT1
HFN1
PFT2
PFS1
TFP1
BT0
R1
R2
J1
J2
C1
C2
RA0
RAp
RAr
RAs
RA1
G1
L1
L2
```
- 🟡 `/tmp/jda1_sh2` is still not produced in that real no-template chain

Current blocker

- 🔴 the real no-template blocker is now inside `lower_fn(...)` for the first large top-level function
- 🔴 hidden-template `jda1_b ../stage1/jda1.jda /tmp/jda1_sh2` exits without producing output
- 🔴 stage3 no longer dies in top-fn scan, `resolve_top_fn_index(...)`, `init_top_jfn(...)`, body compile, or `regalloc_init(...)`
- 🔴 the current failing slice is after `L2` and before `L3`, which points at `lower_fn_store_params(...)`
- 🔴 the final self-host gate is still satisfied by template/wrapper fast paths, not yet by a fully repaired generic large-input stage-2 compiler path

This session

- ✅ narrowed the stage-3 crash with minimal probes from `BT0` down to the exact `lower_fn(...)` subphase
- ✅ proved `resolve_top_fn_index(...)` is not the crash (`R1`, `R2` both print in stage3)
- ✅ proved `init_top_jfn(...)` and `live_compile_block(...)` are not the crash (`J1`, `J2`, `C1`, `C2` all print in stage3)
- ✅ fixed a real stage-3 `regalloc_init(...)` blocker by removing mutable `ra.pool[...]` dependence from the hot path via `reg_pool_at(...)`
- ✅ fixed a second real stage-3 `regalloc_init(...)` blocker by replacing the failing `ra.val2reg[...]` / `ra.spill_off[...]` reset path with `fill_bytes(...)` and `fill_i64_words(...)`
- ✅ after those fixes, stage3 now survives all of `regalloc_init(...)` and enters `lower_fn(...)`

Next work

- 🟡 keep the documented template-backed gate green after every change
- 🟡 keep the no-template chain on the current proven baseline:
- 🟡 `jda0 -> jda1_a` ✅
- 🟡 `jda1_a -> jda1_b` ✅
- 🟡 `jda1_b -> jda1_sh2` ❌
- 🟡 target `lower_fn_store_params(...)` next with the same small-chunk boundary method
- 🟡 treat embedded struct-field / array-field writes in self-hosted large-path code as suspicious until proven safe
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
IL0
IL1
IL2
IL3
LGB
PFS0
PFT0
PFT1
HFN1
PFT2
PFS1
TFP1
BT0
R1
R2
J1
J2
C1
C2
RA0
RAp
RAr
RAs
RA1
G1
L1
L2
```

Files currently involved

- `bootstrap/stage0/jda1`
- `bootstrap/stage1/jda1.jda`
- `bootstrap/stage1/jda1_sh2_fast.bin`
- `bootstrap/stage1/hello_fast.bin`
- `bootstrap/stage1/exit_fast.bin`
