# Jda Self-Hosting: Architectural Fixes and Stabilizations

This document details the critical architectural fixes and stabilizations implemented to resolve memory corruption and bootstrap blockers in the Jda compiler pipeline.

## 1. Root Cause Analysis: The `jfn.src = 0` Corruption

Exhaustive machine code analysis using `ndisasm` and trace diagnostics revealed that the `jfn.src` pointer was being clobbered shortly after initialization.

### Issues Identified:
1.  **Struct Misalignment:** The `JirFunction` struct and global variables lacked 8-byte alignment. This caused 64-bit pointers to be stored at non-aligned addresses, leading to corruption on modern architectures and incorrect offset calculations in the `jda0` bootstrap compiler.
2.  **Outdated Struct Offsets:** `jda0.asm` relied on hardcoded field offsets that did not match the evolved `JirFunction` definition in `jda1.jda`. As the struct grew (specifically the `BasicBlock` array), these offsets became invalid, causing the compiler to clobber adjacent memory.
3.  **Address Space Overflow:** `jda0` used 32-bit registers (`edi`, `esi`) for `mmap` sizes and `imul` arithmetic. With `JirFunction` growing to ~6.3 MB, large table allocations exceeded the 32-bit limit, leading to address space exhaustion and segfaults.
4.  **Symbol Conflicts:** Conflicting label names between the compiler's internal globals (e.g., `src_len`, `tok_cnt`) and the auto-generated constants from `jda1.jda` caused NASM to miscalculate memory addresses.

## 2. Implemented Fixes

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

## 3. Current Status

The `jda0 -> jda1_a` stage is now stable. The compiler successfully performs:
-   Lexical analysis of the entire `jda1.jda` source.
-   Pass 1 global function scanning.
-   Successful entry into Pass 2 code generation.

The pipeline currently reaches the following state:
```sh
./jda0 ../stage1/jda1.jda jda1_a # Passes LEX and P1
```

## 4. Next Steps to Achieve Full Self-Host

1.  **Optimize `JirFunction` Size:** The current `JirFunction` is ~6.3 MB, which approaches the limits of `jda0`'s memory model. Reducing the `BasicBlock` or `Instr` array capacities will improve stability and speed up the bootstrap.
2.  **DCE and Register Allocation:** Once Pass 2 lower completes for all functions, verify the Dead Code Elimination (DCE) and Register Allocation phases in `jda1_a`.
3.  **No-Template Finalization:** Complete the `jda1_a -> jda1_b` compilation to produce a compiler that is entirely built from its own source without using any pre-compiled templates.
4.  **Verification:** Compile `examples/hello.jda` with the final `jda1_sh2` binary to achieve the "Hello Bare Metal" milestone.
