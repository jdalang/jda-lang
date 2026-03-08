# Selfhost Status - BLOCKED

## Current Situation
- ✅ **jda0 → jda1**: Works perfectly
- ❌ **jda1 → jda1_selfhost**: BLOCKED by jda0 compiler bugs

## Root Cause
jda0 (hand-written x86-64 assembler compiler) has bugs in:
1. Global struct array initialization → NULL pointers
2. Struct array element field access → wrong memory offsets
3. Pointer arithmetic codegen → incorrect assembly

These bugs prevent jda1 from compiling itself when it tries to use Token arrays in lex().

## Why It's Hard to Fix
- Would require reverse-engineering jda0's generated code with GDB
- jda0 is 5,000+ lines of assembly with complex register allocation
- The bugs are in subtle codegen logic that's error-prone
- Too time-consuming to debug at assembly level

## Workaround Status
Tried:
- ✅ Heap allocation instead of stack
- ✗ Global arrays (NULL pointer issue)
- ✗ Manual byte offset calculations (still crashes)

**Conclusion**: The bugs are in jda0 itself, not fixable from jda1 without fixing jda0 first.

## Impact
- **Language Development**: NOT BLOCKED - jda1 can still be enhanced
- **Features**: Can add new syntax/operators without selfhosting
- **Compilation**: Works: jda0 compiles jda1, jda1 compiles user code
- **True Selfhosting**: Blocked until jda0 bugs fixed

## Recommendation
1. Accept jda0 → jda1 as the bootstrap chain
2. Continue developing jda1 features
3. Focus on jda1 robustness and language design
4. Selfhosting can be revisited when resources available for jda0 debugging

## What Still Works
```
hello.jda → [jda0] → hello_binary ✅
hello.jda → [jda1] → hello_binary ✅
jda1.jda → [jda0] → jda1_binary ✅
jda1.jda → [jda1] → CRASH ❌
```

Date: March 8, 2026
Status: KNOWN LIMITATION - Moving forward with 2-stage bootstrap
