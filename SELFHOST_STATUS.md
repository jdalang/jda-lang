# Jda Self-Hosting Status

## Current Status: STAGE 1B REACHED (Partially Stable)
**Date:** March 25, 2026

### Progress Summary
- [x] Stage 0 compiles Stage 1 source -> `stage1_a` (SUCCESS)
- [x] `stage1_a` compiles Stage 1 source -> `stage1_b` (SUCCESS)
- [ ] `stage1_b` compiles `hello.jda` (FAILING - Segfault during init)

### Recent Major Fixes
1. **Comparison Logic:** Fixed `jda0` clobbering `r12` and `rax` during RHS evaluation in comparisons.
2. **Stack Protection:** Implemented robust `save_pool`/`restore_pool` to maintain stack symmetry across syscalls.
3. **Table Expansion:** Increased `JirFunction` limits to 512 blocks and 1024 variables.
4. **Toolchain Sync:** Fixed `generate_jda0_spec.py` to dynamically calculate struct sizes, ensuring Stage 0 uses correct memory offsets.
5. **Parser Recovery:** Fixed `live_compile_block` to correctly handle brace nesting and prevent token skipping.

### Known Issues
- `stage1_b` (the bootstrapped binary) segfaults early in execution. Suspected causes:
    - ELF header inconsistency (currently using 64-byte phoff with 120-byte total header).
    - Global data segment initialization in the generated binary.
    - Stack alignment during `alloc_pages` calls.

### Next Steps
- Finalize the ELF data segment logic in `write_elf`.
- Verify stack alignment (16-byte) for all generated function calls.
- Reach full stable self-hosting (Stage 1b compiles hello.jda).
