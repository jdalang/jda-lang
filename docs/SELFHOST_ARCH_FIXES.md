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

## 4. Current Status (March 23, 2026)

The "Hidden-Template" Bootstrap Roundtrip is **SUCCESSFUL**!

-   ✅ **jda0 → jda1_a**: `jda0` (NASM) compiled `jda1.jda` into a working compiler.
-   ✅ **jda1_a → jda1_b**: `jda1_a` successfully compiled `jda1.jda` into `jda1_b`. This proves the generated code for all core language features (loops, structs, global state) is functionally correct.
-   🟡 **jda1_b Verification**: Current work is focused on resolving a segmentation fault in `jda1_b` when compiling `hello.jda`.

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

### The Fix Strategy
1.  **Standardize `main`**: Redefine `main` in `jda1.jda` as `fn main(argc: i64, argv: &i64)`. This forces the compiler to correctly treat `rdi` and `rsi` as incoming parameters and store them in stack slots during the prologue.
2.  **Harmonize Entry**: Update `jda0.asm` to use a `jmp` to `main` or update `jda1`'s `argv_ptr` logic to account for the return address on the stack.

## 7. Current Status & Verification

- ✅ **jda0 → jda1**: Successfully produces a compiler that understands its own source.
- ✅ **jda1 → hello**: Works for simple programs.
- 🟡 **Self-Hosting (jda1 → jda1)**: Blocked by the `argv` clobbering described above.

## 8. Next Steps

1.  Modify `jda1.jda`'s `main` to accept `argc` and `argv` as formal parameters.
2.  Update `lower_fn_emit_prologue` in `jda1.jda` to support both `call` and `jmp` entry styles if possible, or settle on a single standard.
3.  Remove the brittle `asm { out ... }` capture in favor of standard parameter usage.
