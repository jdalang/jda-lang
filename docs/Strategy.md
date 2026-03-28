# Jda Compilation Strategy

Latest checkpoint (2026-03-24):

## Pipeline Status

- ✅ **jda0 (NASM)**: Stable bootstrap compiler.
- ✅ **jda1_a (Gen 1)**: First-generation Jda compiler, built by jda0.
- ✅ **jda1_b (Gen 2)**: Second-generation Jda compiler, built by jda1_a.
- ✅ **Self-Hosting Roundtrip**: `jda1_b` successfully compiles `hello.jda` into a working `hello_sh` binary.
- ✅ **Output**: `Hello Bare Metal` verified.

## Breakthroughs & Fixes

### 1. Main ABI Harmonization
- Resolved register clobbering by using standard parameter passing (`main(argc, argv_ptr)`).
- Forced the compiler to preserve `rdi` and `rsi` into stack slots immediately upon entry.

### 2. Structural Synchronization
- Synchronized `JirFunction` and `LowerCtx` structures between `jda1.jda` and `tools/jda0_spec.py`.
- Finalized reduced sizes (128 blocks, 64 vars) to ensure both stability and bootstrap speed.

### 3. String Math Correction
- Fixed a 3-byte offset error in `jda0.asm` string pointer math.
- Corrected relative displacement calculation to account for the full 7-byte `lea` instruction.

### 4. Robust Diagnostics
- Implemented `eprint_i64` without relying on unsupported operators.
- Added safety breaks to loops to prevent hangs during bootstrap.

## Verified Roundtrip Workflow

The following pipeline is now 100% stable and automated:

1. **Bootstrap**: `nasm` + `ld` → `jda0`
2. **Generation 1**: `jda0` compiles `jda1.jda` → `jda1_a`
3. **Generation 2**: `jda1_a` compiles `jda1.jda` → `jda1_b`
4. **Validation**: `jda1_b` compiles `hello.jda` → `hello_sh`
5. **Execution**: `./hello_sh` → `Hello Bare Metal`

## Next Phase: Minimal Release (Stage 2)

1. **CLI Stabilization**: Unified `jda build` and `jda run`.
2. **Error Diagnostics**: Line/column reporting.
3. **Standard Library**: Expanded `jda::fs`, `jda::time`, and `jda::fmt`.
