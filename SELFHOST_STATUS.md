# Selfhost Status - PROGRESS (Critical Bug Found & Partially Fixed) ⚠️

## Current Situation
- ✅ **jda0 → jda1**: Works perfectly
- ✅ **jda0 code generation**: Major breakthrough - automated generator eliminates hardcoding (Phases 1-3 complete)
- ✅ **jda1 → simple programs**: NOW WORKING - jda1 successfully compiles hello.jda!
- ❌ **jda1 → jda1_selfhost**: Partially blocked - jda1 crashes in lex() when processing itself

## Recent Fix: Pointer Arithmetic Segfault (March 8, 2026)
**Commit**: `6b8542e` - resolve jda1 pointer arithmetic segfault by using stack-allocated token buffer

### The Bug
- jda1 crashed with segfault when accessing Token structures via `alloc_pages()` returned pointers
- **Root cause**: jda0's codegen doesn't correctly calculate struct-sized offsets through byte pointers (`&i8`)
- When accessing `toks[pos].type` where `toks` was `&i8` from `alloc_pages(16)`, the generated x86-64 code used wrong offset calculations
- Result: reading from uninitialized/invalid memory → segmentation fault

### The Fix
- Changed token buffer allocation from heap (`alloc_pages(16)` → `&i8`) to stack (`Token[15000]`)
- Now jda0 knows the correct type and generates proper struct-sized offset calculations
- Tradeoff: 420 KB of stack space vs. correct functionality
- Status: **jda1 now successfully compiles hello.jda** ✅

## Major Breakthrough: Automated jda0 Code Generator
**Branch**: `feature/jda0-code-generator`

### Completed Phases (60%)
1. **Phase 1 ✅**: Spec extraction tool (`generate_jda0_spec.py`)
   - Parses jda1.jda automatically
   - Extracts 45 token types, 10 type constants, 28 opcodes, 11 structures
   - Breaks architectural bottleneck — changes to jda1 no longer require manual jda0 edits

2. **Phase 2 ✅**: Constant generator (`generate_jda0_constants.py`)
   - Generates 4,961 bytes of NASM constants
   - Includes compatibility layer

3. **Phase 3 ✅**: Struct offset generator (`generate_jda0_structs.py`)
   - Generates 3,620 bytes of field offset equations

4. **Phase 5 VALIDATION ✅**: jda0 built with generated constants successfully compiles `hello.jda`

### Previous Issues (Now Understood)
jda0 had bugs that appeared unfixable at assembly level:
- Global struct array initialization → NULL pointers
- Struct array element field access → wrong offsets
- Pointer arithmetic codegen → incorrect assembly

**Resolution**: Generated code avoids these patterns; validates jda0's core logic works when properly constructed.

## Second Fix: lex() String Escape Bounds Checking
**Commit**: `9e9a315` - correct lex() string escape handling and bounds checking

### The Bug #2
- lex() crashed when processing files with escape sequences (especially near EOF)
- Original code: `pos += 2` unconditionally when encountering backslash in string
- This could move `pos` past `src_len`, causing out-of-bounds access

### The Fix #2
- Increment pos by 1, then conditionally increment again if in bounds
- Check that closing quote exists before skipping it
- Prevents buffer overrun when escape sequences appear near EOF

### Result
- ✅ lex() successfully processes large files and jda1.jda without crashing!
- jda1 can now lex jda1.jda completely

## Remaining Self-Hosting Blocker
**Issue**: jda1's parser doesn't support `const` declarations
- ✅ hello.jda → [jda1] → hello_binary ✅ (WORKS)
- ✅ jda1.jda lex phase → [jda1] → completes successfully ✅ (NEWLY FIXED)
- ❌ jda1.jda parse phase → [jda1] → **Blocked: parser doesn't handle `const` syntax** ❌
- Root cause: jda1.jda starts with 40+ const declarations, but jda1's parser only looks for `fn` declarations
- Solution needed: Either (1) implement const declaration parsing in jda1, or (2) move const declarations out of the main syntax

## Current Compilation Chain
```
hello.jda → [jda0] → hello_binary ✅
jda1.jda → [jda0] → jda1_binary ✅
hello.jda → [jda1] → hello_binary ✅ (NEWLY WORKING!)
jda1.jda (lex) → [jda1] → tokens ✅ (NEWLY WORKING!)
jda1.jda (parse) → [jda1] → AST ❌ (blocked: needs const parsing)
```

## Next Steps
1. **Implement const declaration parsing in jda1** - allows full self-hosting
2. **Parse jda1.jda with jda1** - reaches codegen phase
3. **Debug any remaining codegen issues** - achieve full self-hosting roundtrip
4. **Phase 4-5**: Token/opcode handler generation for jda0 code generator

## Impact
- **Language Development**: Full speed ahead — architecture no longer bottlenecked by hardcoding
- **Self-Hosting**: Achievable with generated code approach
- **Maintainability**: jda1 changes automatically propagate to jda0

Date: March 8, 2026
Status: MAJOR PROGRESS - Automated code generation breaks 5K-line hardcoding bottleneck
