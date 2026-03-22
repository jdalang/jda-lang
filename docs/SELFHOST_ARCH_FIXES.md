# Jda Self-Hosting: Architectural Fixes and Stabilizations

This document details the critical architectural fixes and stabilizations implemented to resolve memory corruption and bootstrap blockers in the Jda compiler pipeline.

## 1. Root Cause Analysis: The `jfn.src = 0` Corruption

Exhaustive machine code analysis using `ndisasm` and trace diagnostics revealed that the `jfn.src` pointer was being clobbered shortly after initialization.

### Issues Identified:
1.  **Struct Misalignment:** The `JirFunction` struct and global variables lacked 8-byte alignment. This caused 64-bit pointers to be stored at non-aligned addresses, leading to corruption on modern architectures and incorrect offset calculations in the `jda0` bootstrap compiler.
2.  **Outdated Struct Offsets:** `jda0.asm` relied on hardcoded field offsets that did not match the evolved `JirFunction` definition in `jda1.jda`. As the struct grew (specifically the `BasicBlock` array), these offsets became invalid, causing the compiler to clobber adjacent memory.
3.  **Address Space Overflow:** `jda0` used 32-bit registers (`edi`, `esi`) for `mmap` sizes and `imul` arithmetic. With `JirFunction` growing to ~6.3 MB, large table allocations exceeded the 32-bit limit, leading to address space exhaustion and segfaults.
4.  **Symbol Conflicts:** Conflicting label names between the compiler's internal globals (e.g., `src_len`, `tok_cnt`) and the auto-generated constants from `jda1.jda` caused NASM to miscalculate memory addresses.

## 2. Implemented Fixes (Phase 1 & 2)

### Automated Synchronization (Phase 4 Completion)
-   **Dynamic Spec Generation:** Updated `tools/generate_jda0_spec.py` to correctly identify `i64` as 8 bytes and enforce **8-byte alignment** for all struct fields.
-   **NASM Header Integration:** Modified `jda0.asm` to use `%include "jda0_structs.asm"` and `%include "jda0_constants.asm"`, replacing all hardcoded sizes and token types.
-   **Reserved Name Exclusion:** Updated the generator to skip constants that conflict with `jda0`'s internal globals, ensuring stable symbol resolution.

### Compiler Robustness
-   **64-bit Memory Mapping:** Updated `mmap_anon` and its callers in `jda0.asm` to use 64-bit registers (`rdi`, `rsi`) for allocation sizes.
-   **Safe Arithmetic:** Replaced `imul rax, rax, imm32` with a 64-bit sequence (`mov r11, FN_SZ; imul rax, r11`) to prevent signed dword overflows with large structure sizes.
-   **Globalized Critical Pointers:** In `jda1.jda`, critical pointers like `g_jfn` and `g_jfn_heap` were moved to the global scope to eliminate loop-local stack corruption bugs in the bootstrap compiler.

### Memory Layout Stabilization
-   **BSS Alignment:** Added `align 8` to the `.bss` section in `jda0.asm` and ensured that all pointer variables are correctly aligned.
-   **Global Alignment:** Updated `add_global` in `jda0.asm` to enforce 8-byte alignment for every global variable offset.

## 3. Advanced Stabilizations (Phase 3 - March 2026)

### Global-Based Position Tracking
-   **Register Clobber Bypass:** Identified that `jda0` incorrectly allocates function arguments (like `pos: &i64`) in caller-saved registers that are clobbered by nested calls (e.g., `parse_struct_decl` -> `tok_type_at`).
-   **The Fix:** Refactored `jda1.jda` to use a global `g_main_pos` variable. Updated `expect`, `parse_type`, `parse_fn`, and all `run_top_*` loops to update this global directly instead of passing a pointer.
-   **Result:** Resolved the "5 of 11 structs" parsing failure. The compiler now successfully parses the entire 60k-token codebase.

### Expression Parser Resilience
-   **Type Annotation Skipping:** Fixed a persistent `parse error` where `jda0` choked on colon-prefixed type annotations in expressions (e.g., `3:i64`). 
-   **The Fix:** Modified the `maybe_binary` loop in `jda0.asm` to explicitly identify and skip `TOK_COLON` and the following type/pointer tokens.

### Dynamic Buffer Migration
-   **Heap-Allocated Source:** Completely replaced the static `src_buf` BSS array with a heap-allocated `src_buf_ptr` initialized via `mmap`. This allows the compiler to handle source files larger than the hardcoded 1MB limit.
-   **Stack Expansion:** Increased the `jda0` stack size to 8MB in the `Makefile` to prevent overflows during deep recursive parsing of complex functions.

## 4. Current Status (March 24, 2026)

Stage 1 is stable, but full self-hosting is not yet passing end-to-end.

-   ✅ **`jda0 -> jda1_a`**: `jda0` (NASM) compiles `jda1.jda` into a working Stage 1 compiler.
-   ✅ **`jda1_a -> hello`**: `jda1_a` correctly receives command-line arguments and compiles `hello.jda` into a working executable.
-   ❌ **`jda1_a -> jda1_b`**: self-hosting fails. `jda1_selfhost` (the self-hosted binary) exits 0 without producing an output file. No panic or error message is emitted; the compiler silently reaches `syscall(60, 0)` before the ELF write path.
-   🟡 **Current focus**: dynamic frame sizing and stack-floor fixes are confirmed working; the remaining blocker is the silent early-exit during self-hosting compilation.

## 6. Command Line Argument Root Cause Analysis (March 23, 2026)

Detailed investigation into the `argc`/`argv` failure in `jda1` revealed a fundamental ABI mismatch between the bootstrap stages.

### The Discrepancy: `call` vs `jmp`
1.  **Stage 0 (`jda0.asm`)**: The generated `_start` stub uses `call main`.
    -   Stack at `main` entry: `[rsp]` = return address, `[rsp+8]` = `argc`, `[rsp+16]` = `argv[0]`.
    -   Registers at `main` entry: `rdi` = `argc`, `rsi` = `argv` (base pointer).
2.  **Stage 1 (`jda1.jda`)**: The `lower_fn_emit_prologue` and `OP_ARGV_BASE` assume a `jmp`-style entry (standard for many minimal ELFs).
    -   Expected stack: `[rbp+16]` = `argv[0]`.
    -   However, because `jda0` used `call`, `[rbp+16]` in `main` actually points to `argv[0]` *if and only if* `main` was JUMPED to. With a `call`, `[rbp+8]` is the return address, and `[rbp+16]` is `argc`.

### Parameter Mismatch
-   In `jda1.jda`, `main` is defined as `fn main()`. It takes **zero parameters**.
-   `jda0` compiles `main` as a zero-parameter function, meaning its prologue does not preserve `rdi` or `rsi`.
-   `jda1`'s `main` tries to capture arguments via `asm { out argc = rdi }`. If `jda0`'s prologue clobbers `rdi` (e.g., for large stack frame adjustments or `mmap` calls), the value is lost before the `asm` block executes.

### Implemented Fixes (March 23-24, 2026)

1.  **Stack-Based Argument Capture**: Modified `jda1.jda`'s `main()` to load `argc` and `argv_ptr` directly from the stack using standard parameter passing. This eliminated reliance on registers that were being clobbered.
2.  **Structural Synchronization**: Fixed a major memory corruption issue where `JirFunction` and `LowerCtx` structures were out of sync between `jda1.jda` and the `tools/jda0_spec.py` used by the bootstrap compiler. The current stabilized layout uses 128 blocks and 256 variables.
3.  **Corrected String Displacement**: Fixed a 3-byte error in `jda0.asm` string pointer math. The relative offset calculation now correctly accounts for the full 7-byte length of the `lea rax, [rip + displacement]` instruction.
4.  **Robust Diagnostics**: Implemented `eprint_i64` without relying on unsupported operators like `%` or `as`, resolving infinite loops during early bootstrap debugging.
5.  **Address-Of Semantics**: Fixed the `&` operator so pointer-typed expressions are no longer incorrectly dereferenced during bootstrap compilation.
6.  **Stack Slot Reset**: Corrected `init_top_jfn()` so `jfn.next_slot_off` now starts at `0` instead of `65536`. This removes the accidental 64 KiB local-frame floor that previously affected every compiled function.
7.  **Dynamic Frame Sizing**: Reworked `lower_fn_emit_prologue()` to reserve stack space based on actual local and spill usage. The frame size is now backpatched after lowering, and the spill allocator starts above `jfn.next_slot_off` so local slots and spills do not overlap.

## 7. Current Status & Verification

- ✅ **`jda0 -> jda1_a`**: Successfully produces a functional bootstrap compiler.
- ✅ **`jda1_a -> hello_sh`**: Correctly compiles simple programs with working strings and arguments.
- ✅ **Stack-floor diagnosis validated**: the hardcoded `next_slot_off = 65536` initialization was real and has been removed.
- ✅ **Generated prologues shrank**: Stage 1 now emits compact per-function stack frames instead of reserving a fixed 512 KiB / 2 MiB frame.
- ✅ **`jda1_a -> jda1_selfhost`**: binary produced (no longer a segfault during compilation).
- ❌ **`jda1_selfhost` silent exit**: the self-hosted compiler exits 0 without writing output, even for `hello.jda`. No panic or error is printed; the bug is a silent early-exit somewhere in the top-level compilation loop.
- 🟡 **Important conclusion**: the compile-time crash is gone; the remaining blocker is a logic error causing the compiler to exit before reaching `write_elf`.

## 8. Phase 5 Fixes (March 24, 2026)

The following fixes were applied in the current working tree to address the remaining self-hosting failures:

### Return-Type Annotation Fixes
`jda0` requires explicit `-> i64` return-type annotations to emit correct return-value handling. The following functions were missing them and have been corrected:
`load_i8_at`, `load_i8_at0`, `char_at_pos`, `lex_scan_int`, `tok_type_at0`, `tok_type_at`,
`tok_imm_at`, `tok_str_start_at`, `tok_str_len_at`, `parse_const_decl`,
`skip_top_level_let_rhs`, `skip_top_level_let`, `char_to_tok`, `lower_fn_emit_prologue`.

### Variable Table Expansion
-   **`VarEntry` array**: expanded from `VarEntry[64]` to `VarEntry[256]` in `JirFunction`, eliminating "Too many vars" panics when compiling large functions.
-   **`bind_name` limit**: guard raised from `>= 128` to `>= 256` to match.
-   **Struct size update**: `FN_SZ` = 3,161,288 bytes; `jda0_constants.asm` and `jda0_structs.asm` regenerated accordingly.
-   **Hardcoded field indices** in `load_param_slot_at` and `lower_fn_store_params` updated to `395145` / `395144` to reflect the new layout (was `1,575,433` / `1,575,432`).

### i8 Store Instruction Support
-   Added `emit_store_mem_reg8` to emit an 8-bit `MOV [base], src` (`0x88` opcode with REX prefix).
-   `lower_instr_mem` now calls this variant when `ins.itype == TYPE_I8`, fixing memory corruption when storing byte-width values into `&i8` pointers.

### `_start` Stub and Entry-Point Patch
-   **23-byte `_start`**: the emitted `_start` stub now opens with `mov rdi, [rsp]` / `lea rsi, [rsp+8]` before the `call main`, so compiled binaries correctly receive `argc`/`argv` from the kernel stack.
-   **Entry patch offset**: updated to bytes 10–13 (was 1–4); `e_rel = m_off - 14` (was `m_off - 5`).
-   **Main detection**: `str_match` replaced with `streq(src_buf, cur_name_off, 4, "main")` for `is_main` detection; `fn_code_off[0]` is now explicitly set when `is_main == 1`, independent of function scan order.

### `expect()` Signature Fix
All call sites of `expect()` updated to pass the token array explicitly: `expect(toks, TOK_X)` instead of the old no-arg form. This was silently passing a stale/uninitialized pointer in some code paths.

### `live_compile_block` Brace Fix
Two mismatched closing braces in `live_compile_block` caused the per-iteration parser recovery guard (`if g_main_pos <= before_stmt`) to execute outside the loop rather than at the end of each iteration. The braces have been corrected so the guard is inside the loop body where it belongs.

### `jda0.asm` Address-Of Fix
-   Removed an erroneous extra `mov rax, [rax]` dereference in `gen_expr_base` that was unconditionally loading through the pointer after emitting `gen_addr` for `&ptr` expressions. This caused double-indirection for every `&` expression on a pointer-typed variable.
-   Fixed `gen_addr` array indexing to unconditionally write `lv_isptr = 0` after processing an index expression (rather than restoring the old value), since the result of `arr[i]` is always an element, not a pointer.
-   Removed a stale `pop rax` in `p2_gen` that was popping without a matching push, corrupting the stack during ELF generation.

### Struct Size Updates
| Constant | Old | New |
|---|---|---|
| `FN_SZ` | 12,603,464 | 3,161,288 |
| `LOWER_SZ` | 102,512 | 99,440 |
| `GLB_SZ` | 48 | 32 |

## 9. Next Steps

1.  **Fix silent early-exit in `jda1_selfhost`**: trace why the self-hosted compiler exits 0 before `write_elf`. Suspected cause: a `live_compile_block` brace issue causing incorrect control flow in the outer function-scan loop, or an `argc` check being triggered due to residual register state.
2.  **Remove remaining debug noise**: one `eprint("DEBUG: argc = ...")` call remains at the top of `main()` and must be removed before shipping.
3.  **Verify `jda1_selfhost -> hello`** compiles and runs correctly once the silent-exit is fixed.
4.  **Stage 3 roundtrip**: run `jda1_selfhost -> jda1_selfhost2` to confirm full self-hosting stability.
5.  **Upstream fixes**: merge into main after self-hosting and conformance both pass.
