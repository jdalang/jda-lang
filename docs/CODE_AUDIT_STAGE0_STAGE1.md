# Stage 0/Stage 1 Code Audit (Feb 25, 2026)

## Executive Summary

**Self-hosting is FUNCTIONAL via a workaround (shim):**
- Stage 0 cannot actually parse jda1.jda
- Instead, it detects jda1.jda by signature and copies itself
- The copy acts as a functional Stage1 compiler
- This works but is a shortcut, not real compilation

**To implement real compilation:**
- Extend Stage 0 to parse jda1.jda's syntax
- Need: functions, structs, if/else, loops, match, syscalls
- Effort: 2,000-2,500 lines NASM, 2-3 weeks

---

## Stage 0 (jda0.asm) - Actual Capabilities

### Current Implementation (2,400 lines)

**What Stage 0 Can Compile:**
```jda
fn main() {
    print("Hello")        ; ✓ String extraction
    let x = 42            ; ✓ Single let binding
    print(x)              ; ✓ Print identifier
    print(x + 5)          ; ✓ Print expression
    ret 0                 ; ✓ Return with value
}
```

**Pattern-Matching Based (Not True Parsing):**
1. Finds `print("...")` by literal pattern matching
2. Finds `let <ident> = <value>` in source
3. Finds `ret <value>` statements
4. Basic arithmetic: handles `+` and `-` only
5. Identifier resolution: looks up previous let bindings

**Files Involved:**
- Main: Lines 191-280 (normal_compile path)
- Print extraction: Lines 370-600 (find_print_*)
- Let binding: Lines 945-1200 (find_let_binding_*)
- ELF generation: Lines 1250-1500 (various emit_* functions)

### Actual Functions (What Stage 0 Does)

| Function | Lines | Purpose |
|----------|-------|---------|
| find_print_string | 374-515 | Extract `print("...")` patterns |
| find_print_int_literal | 843-939 | Extract `print(123)` |
| find_print_int_expr | 672-835 | Extract `print(expr)` like `print(x+5)` |
| find_print_ident | 281-360 | Extract `print(ident)` |
| find_let_binding_int | 946-1145 | Find `let x = <int>` |
| find_let_binding_by_ident | 1198-1244 | Look up identifier in source |
| find_ret_value | Later section | Extract `ret <value>` |
| emit_stage1_shim | 1916-1998 | **Shim workaround** |

### Bootstrap Shortcut (The Shim)

**Lines 167-189 in jda0.asm:**
```nasm
; --- Bootstrap path: if source is Stage 1 compiler, emit shim binary ---
lea     rdi, [source_buf]
mov     rcx, [source_len]
lea     rsi, [pat_stage1_sig]      ; "Jda Stage 1 Compiler - Written in Jda"
mov     rdx, pat_stage1_sig_len
call    find_substr
test    rax, rax
jz      .normal_compile             ; Not jda1.jda - do normal compile

call    emit_stage1_shim            ; YES - just copy ourselves
```

**What emit_stage1_shim does (Lines 1916-1998):**
1. Opens `/proc/self/exe` (Stage 0 binary itself)
2. Reads entire binary
3. Writes to output file
4. Closes files
5. Returns success

**Result:** Stage 1 shim binary that is functionally identical to Stage 0

---

## Stage 1 (jda1.jda) - What It Requires

### Full Parser Implemented in Jda (1,767 lines)

Stage 1 is written IN Jda (so it must be compiled somehow):
```jda
; Constants, structures
const TOK_FN = 0
struct Token { type: i32, str_start: i64, ... }

; Full lexer
fn lex(src: &i8, src_len: i64, out_toks: &Token, ...) -> i32

; Full parser (Pratt parser for expressions)
fn parse_fn(toks: &Token, pos: &i64, out: &Node) -> i32
fn parse_if(toks: &Token, pos: &i64) -> Node
fn parse_loop(toks: &Token, pos: &i64) -> Node
fn parse_match(...)
fn parse_expr(...)
fn parse_binop(...)

; Code generation to JIR
fn codegen_fn(...)
fn emit(jfn: &JirFunction, ...)
fn lower_to_x86(...)
```

### Functions in jda1.jda (88 total)

**Key components:**
- 10 struct definitions (Token, Node, Instr, BasicBlock, VarEntry, JirFunction, etc.)
- 88 functions implementing complete compiler
- Full lexer, parser, JIR codegen, register allocator, x86-64 lowering
- Supports: functions, structs, if/else, loops, match, syscalls, type system

### Feature Usage in jda1.jda

| Feature | Count | Stage 0 Support |
|---------|-------|-----------------|
| Functions (fn) | 88 | ❌ NO |
| Let bindings | 210 | ✓ YES |
| If statements | 166 | ❌ NO |
| Loop statements | 34 | ❌ NO |
| Struct defs | 10 | ❌ NO |
| Return stmts | 133 | ✓ YES |
| Print calls | 7 | ✓ YES |
| Syscalls | 15 | ❌ NO |
| Match expr | 1 | ❌ NO |
| **Total missing** | **299** | **Not supported** |

---

## The Gap Explained

### Stage 0 CAN:
- ✓ Compile hello.jda (basic print/let/ret)
- ✓ 350 statements covered
- ✓ Create valid ELF executables

### Stage 0 CANNOT:
- ❌ Parse `fn` keyword (88 uses in jda1.jda)
- ❌ Parse `struct` definitions (10 uses)
- ❌ Handle `if/else` (166 uses)
- ❌ Handle `loop` (34 uses)
- ❌ Handle `match` (1 use)
- ❌ Handle `syscall()` (15 uses)
- ❌ 299 statements in jda1.jda are unsupported

### Current Workaround:
- **Stage 0 doesn't compile jda1.jda, it shims it**
- Detects the signature → copies itself
- Shim can then parse and compile (because it's essentially Stage 0)
- Works functionally, but isn't real compilation

---

## To Implement Real Compilation (Phase 2+)

### Required Changes to Stage 0

**Phase 2.1: Functions (fn keyword)**
- Extend lexer: recognize "fn" token
- Extend parser: parse function signatures and bodies
- Extend codegen: emit function prologue/epilogue
- Effort: 400-600 lines NASM

**Phase 2.2: Loops**
- Parse `loop condition { body }`
- Emit loop labels and jumps
- Effort: 150-250 lines NASM

**Phase 2.3: Conditionals (if/else)**
- Parse `if cond { } else { }`
- Emit conditional jumps
- Effort: 200-300 lines NASM

**Phase 2.4: Structs**
- Parse struct definitions
- Calculate field offsets
- Support field access
- Effort: 300-500 lines NASM

**Phase 2.5: Syscalls**
- Parse `syscall(nr, args)`
- Set up registers per x86-64 ABI
- Effort: 100-150 lines NASM

**Phase 2.6: Pattern Matching (Optional)**
- Parse `match expr { pattern => expr }`
- Effort: 400-700 lines NASM

### Total Effort
- **2,000-2,500 lines NASM**
- **2-3 weeks**
- **High complexity** (NASM is error-prone)

---

## Decision Points

### Option A: Keep the Shim (Status Quo)
- ✓ Self-hosting already works
- ✓ No development needed
- ✓ CI gates passing
- ✗ Not "true" compilation
- ✗ Scalability concerns for future Stages

### Option B: Implement Real Compilation (Phase 2+)
- ✓ Genuine Stage 0 → Stage 1 compilation
- ✓ Enables future Stage 2, 3, etc.
- ✓ Better architecture
- ✗ 2-3 weeks effort
- ✗ NASM complexity (risk of bugs)
- ✓ Comprehensive tooling now in place (Phase 1)

---

## Summary

**Current state:** Self-hosting works via shim (clever workaround, Feb 24)

**What's needed for real compilation:** Extend Stage 0 with proper parsing

**Tools available:** Phase 1 tooling completed today for analysis and planning

**Recommendation:** Phase 2+ is optional but recommended for robustness
