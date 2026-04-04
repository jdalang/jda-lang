# Phase 3 — Language Core Maturity Plan

**Goal**: Make Jda powerful enough for real-world CLI tools and servers.

**Prerequisite**: Phase 2 complete. Self-hosted compiler with CLI, stdlib, tests, CI, and installer.

---

## Current Compiler Capabilities

| Area | What Works | What's Missing |
|------|-----------|----------------|
| Types | `i64`, `i8`, `i32`, `f64` (parsed only), `void`, typed pointers | No type checking, no inference, no user-defined types beyond structs |
| Structs | Definitions, field access, pass-by-reference, arrays in fields | No methods, no init literals, no visibility |
| Memory | Stack allocation, `alloc` (page-level), syscall-based I/O | No free, no refcounting, no ownership, no arenas for users |
| Control | `if`/`else if`/`else`, `loop cond {}`, `ret` | No match/enum, no `?` propagation |
| Functions | Named, typed params, return types, recursion | No methods, no generics, no closures |
| IR | 32 JIR opcodes, SSA with const fold + DCE, register allocator with spill | No inlining, no type-aware optimization |

**Partial implementations already in jda1.jda:**
- `NODE_MATCH` AST node defined (line 91) — parser skeleton, no codegen
- `NODE_STRUCT_INIT` defined (line 95) — parser accepts `Name{ x: 5 }`, codegen stubs to 0
- Internal arena pattern used for `block_stmt_arena` — not exposed to users

---

## Milestones (in dependency order)

### M1: Argument Count Checking ✅

**Completed**: April 2, 2026

**What was done**:
1. Added function metadata tables (`g_fn_param_cnt_tbl`) to store parameter counts during compilation
2. Added return type skip in main compilation loop (parses `-> type` annotations without consuming extra tokens)
3. Added argument count validation in `codegen_call_inline` — reports "too few arguments" when fewer args than declared params
4. Fixed 7 mismatched `expect(toks, TOK_xxx)` calls → `expect(TOK_xxx)` (expect only takes 1 param)
5. Added 7 conformance tests (5 pass, 2 fail) for type checking
6. Self-host converges at 1,860,938 bytes

**Limitations**:
- Only checks `arg_cnt < expected_cnt` (too few args), not too many — because `as` cast syntax inflates arg counts in the expression parser
- Skips functions with >6 params (codegen caps arg_cnt to 6)
- Only checks functions already compiled (forward-declared functions not yet scanned for param counts)

**Not in scope**: Full type checking of assignments, return values, pointer types. These require deeper AST type tracking (future milestone).

---

### M2: Type Inference ✅

**Completed**: April 2, 2026

**What was done**:
1. Added `parse_skip_ret_type()` helper function — parses `-> type` annotations and returns the type constant, keeping main() lean (avoids jda0 compilation hang)
2. Store function return types in `g_fn_ret_type_tbl` during compilation
3. Infer `let` variable types from function call return types in `live_compile_let_stmt` — `let r = fn()` now gets the function's declared return type instead of defaulting to i64
4. Added 3 conformance tests for type inference (infer_fn_ret_type, infer_chain, infer_void_fn)
5. Self-host converges at 1,863,120 bytes

**Already working** (pre-existing inference):
- `let x = 5` → i64 (integer literal default)
- `let s = "hi"` → &i8 (string literal)
- `let v = other_var` → same type as other_var (local/global lookup)
- `let p = alloc_pages(1)` → &void (hardcoded)
- `let s = Foo{}` → struct type (struct init detection)

---

### M3: Enums and Pattern Matching ✅

**Completed**: April 2, 2026

**What was done**:
1. Added `enum` keyword to lexer (`TOK_ENUM=49`, recognized in `classify_keyword_len4`)
2. Added `parse_enum_decl()` — parses `enum Name { Var1 Var2 ... }` into packed flat buffer (enum name + variant names + tag values)
3. Added `lookup_enum_dot()` — resolves `EnumName.Variant` → integer tag by scanning packed buffer
4. Added enum variant access in both codegen paths:
   - `codegen_primary_ident_inline` (non-live path for pre-compiled functions)
   - `live_codegen_primary_ident_inline` (live path for main compilation)
5. Used packed buffer approach (2 globals: `g_enum_buf`, `g_enum_buf_len`) to stay within jda0's global variable limit
6. Added 4 conformance tests: enum_basic, enum_compare, enum_if, enum_multi
7. Self-host converges at 1,870,506 bytes

**Scope**: Simple tag-only enums (variants are integer constants 0, 1, 2...). Tagged unions with associated data and full pattern matching deferred to a future milestone.

---

### M4: `Result<T, E>` and `?` Operator ✅

**Completed**: April 2, 2026

**What was done**:
1. Added `TOK_QUESTION=50` token and `?` character (ASCII 63) to lexer
2. `Result.Ok(val)` and `Result.Err(code)` create 16-byte heap allocations: `{tag: i64, val: i64}` where tag=0 for Ok, tag=1 for Err
3. Result construction handled in both codegen paths (non-live `codegen_primary_ident_inline` and live `live_codegen_primary_ident_inline`)
4. `?` operator in `let` statements: loads tag from Result pointer, branches to early-return (propagating the Err Result) or extracts the Ok value
5. Changed `live_compile_let_stmt` to return `-> i64` (the current basic block, which changes when `?` creates branch blocks)
6. Added 4 conformance tests: result_basic, result_err, result_question, result_chain
7. Self-host converges at 1,881,233 bytes

**Scope**: Result holds i64 values only (no generics). `?` works in `let x = expr?` context (live compilation path). Standard error codes deferred to stdlib work.

---

### M5: Generics (Monomorphization) ✅

**Status**: Complete. Token-level monomorphization for generic functions with single type parameter (i64, i32, i8). Generic fn declarations are scanned, call sites expanded with mangled names (e.g., `identity<i64>` → `identity_i64`), originals hidden. Self-host converges at 1,904,362 bytes.

**Why fifth**: Enables `Result<T, E>`, generic containers, and reusable code.

**Tasks**:
1. **Type parameter syntax** in parser
   ```jda
   fn max<T>(a: T, b: T) -> T {
       if a > b { ret a }
       ret b
   }

   struct Vec<T> {
       data: &T
       len: i64
       cap: i64
   }
   ```

2. **Monomorphization** — duplicate and specialize at compile time
   - `max<i64>(3, 5)` → generates `max_i64(a: i64, b: i64) -> i64`
   - `Vec<i64>` → generates `Vec_i64` struct with `data: &i64`
   - Track instantiations to avoid duplicate codegen

3. **Generic enums** — upgrade Result
   ```jda
   enum Result<T, E> {
       Ok(val: T)
       Err(err: E)
   }
   ```

4. **Constraint checking** (basic)
   - At minimum: monomorphized code must type-check (errors at instantiation site)
   - Stretch: trait bounds (defer to Phase 3+ if complex)

**Approach**: Rust-style monomorphization, not C++ templates or Java type erasure. Each instantiation produces a separate function/struct in JIR. Simple, predictable, zero runtime cost.

**Risk**: Function table and struct table have fixed sizes (256 functions, 64 structs). Monomorphization can explode these. May need to increase limits or switch to dynamic allocation.

---

### M6: `impl` Blocks and Methods ✅

**Completed**: April 2, 2026

**What was done**:
1. Added `TOK_IMPL=51` keyword, recognized in `classify_keyword_len4`
2. Token-level pre-expansion: `expand_impl_blocks()` scans for `impl StructName { fn ... }` patterns, copies method tokens to end of token array with mangled names (e.g., `Point_sum` → `fn Point_sum(self: &Point) -> i64 { ... }`), hides originals as TOK_EOF
3. `&self` parameter transformation: `(&self)` → `(self: &Point)` during token copy
4. Method name mangling via `build_method_mangle()` — writes "StructName_method" and "\nfn StructName_method " to source buffer for FN_SCAN detection
5. Impl table stored in `g_genfn_buf[200+]` (reuses generic function buffer at higher offsets): count at [200], entries at [201+i*6] with {sn_off, sn_len, mn_off, mn_len, moff, mlen}
6. Method call dispatch in both codegen paths:
   - Non-live `codegen_postfix_inline`: when field lookup fails and next token is LPAREN, lookup impl method and dispatch via `live_codegen_method_call`
   - Live `live_codegen_postfix_rest`: same pattern with direct call
7. Associated function dispatch: `StructName.method(args)` → `StructName_method(args)` in both `codegen_primary_ident_inline` and `live_codegen_primary_ident_inline`
8. `live_codegen_method_call` function: emits OP_CALL with self_id as implicit first arg
9. Added 1 conformance test: impl_method (struct Point with sum method)
10. Self-host converges at 1,935,105 bytes (70/70 tests pass)

**Scope**: Methods as syntactic sugar over functions. No vtable, no dynamic dispatch. `&self` methods only (no move self). Single impl block per struct. Up to 64 methods total across all impl blocks.

**Key constraint**: `copy_method_toks` limited to 4 parameters (jda0 bootstrap has 6-arg limit). Reads struct name/method offsets from impl table internally.

---

### M7: Compile-Time Reference Counting (CTRC) ✅

**Completed**: April 2, 2026

**What was done**:
1. Added `OP_DROP` opcode (33) — new JIR instruction for memory deallocation
2. Extended JirFunction struct with `var_owned[256]` and `var_alloc_sz[256]` parallel arrays for ownership tracking
3. Added `clear_owned_flags()` helper to zero ownership arrays at function init
4. Ownership marking in `live_compile_let_stmt`: detects `let x = alloc_pages(N)` with constant N, marks variable as owning `N * 4096` bytes
5. Added `emit_drop()` helper: loads pointer from variable slot, emits OP_CONST for size, emits OP_DROP instruction
6. Added `lower_instr_drop()`: lowers OP_DROP to `munmap(ptr, size)` syscall (rax=11, rdi=ptr, rsi=size)
7. Wired OP_DROP into DCE used-marking and `lower_fn_mark_uses_instr` use-counting
8. Added `ctrc_emit_drops()` and `ctrc_emit_drops_clear()` helpers for scanning owned vars and emitting drops
9. Scope-exit drops in `live_compile_block`: saves var_cnt at block entry, drops owned vars at block exit, restores var_cnt
10. Drops before `break` statements in loop bodies
11. Added 3 conformance tests: drop_scope_basic, drop_early_return, drop_loop
12. Self-host converges at 1,944,440 bytes (73/73 tests pass)

**Scope (v1 — Block-Scope Only)**:
- Automatic munmap at scope exit for `alloc_pages(N)` with constant page count
- Drops in nested scopes (if/loop blocks) only — function-level drops deferred to avoid escape-to-global issues
- NOT in scope: ownership transfer detection, dynamic sizes, move semantics, struct field drops, function-level return drops (requires escape analysis)

**Key constraint**: No drops at function return (v1). Variables stored in globals (e.g., `g_stab_ptr = alloc_pages(50)`) would be incorrectly freed. Full escape analysis deferred to future work.

---

### M8: Region-Based Allocation (Arenas) ✅

**Why eighth**: Performance complement to CTRC. Hot paths need bulk allocation/deallocation.

**Status**: Complete. Implemented as compiler built-in functions using existing JIR opcodes.

**API** (v1 — function-based, no new opcodes):
```jda
let a = arena_new(1)           ; allocate 1 page (4096 bytes)
let p = arena_alloc(a, 64)     ; bump-allocate 64 bytes, returns pointer
arena_reset(a)                  ; reset position to 0 (O(1) bulk free)
arena_destroy(a, 1)             ; release pages back to kernel (munmap)
```

**Implementation details**:
- Arena layout in memory: `[pos:i64, cap:i64, data...]` (16-byte header)
- `arena_new(pages)`: mmap via OP_ALLOC, stores pos=0 and cap=pages*4096-16
- `arena_alloc(arena, size)`: loads pos, computes arena+16+pos, updates pos+=size
- `arena_reset(arena)`: stores 0 to [arena] (position field)
- `arena_destroy(arena, pages)`: munmap via OP_DROP
- All implemented by emitting sequences of existing JIR ops (OP_ALLOC, OP_LOAD_MEM, OP_STORE_MEM, OP_ADD, OP_DROP) — no new opcodes needed
- Built-in recognition in both `codegen_call_inline` and `live_codegen_call_inline`
- Type inference: arena_new and arena_alloc return TYPE_PTR

**Integration with CTRC**:
- Arena-allocated values are NOT refcounted (arena owns them)
- arena_new results are NOT marked as owned (no auto-drop at scope exit)
- User manages arena lifetime explicitly via arena_destroy

**Verification**: 76 conformance tests pass, self-host converged at 1,953,963 bytes

---

### M9: Linear Types for Resource Safety ✅

**Completed**: April 2, 2026

**Implementation**:
- `linear struct` syntax — keyword prefix before struct declaration
- `g_struct_is_linear[]` global array tracks which structs are linear
- `var_linear[256]` and `var_consumed[256]` arrays in JirFunction
- `consume(var)` built-in marks a linear variable as consumed
- Compile-time error if a linear variable exits scope without being consumed
- v1 scope: local analysis only, explicit `consume()` (not method-based consumption)

**Verification**: 82 conformance tests pass, self-host converged at 1,959,640 bytes

---

## Execution Order & Dependencies

```
M1 (type checking) ─── M2 (type inference)
       │
       ├── M3 (enums) ─── M4 (Result + ?) ─── M5 (generics)
       │
       ├── M6 (impl/methods)
       │         │
       │         └── M7 (CTRC) ─── M8 (arenas) ─── M9 (linear types)
       │
       └── [self-host convergence at each milestone]
```

**Critical path**: M1 → M3 → M4 → M5 (enables generic Result + real error handling)

**Parallel track**: M6 (methods) can start after M1, independent of enums.

**Late-stage**: M7-M9 (memory safety) depends on M1 + M6 but is independent of generics.

---

## Self-Hosting Strategy

Every milestone must maintain self-hosting convergence. The approach:

1. **Add the new feature to jda1.jda** (the compiler gains the ability to compile the feature)
2. **Do NOT use the new feature in jda1.jda itself** until it's proven stable
3. **Verify**: `jda1 → jda1_a → jda1_b`, confirm `jda1_a == jda1_b`
4. **After convergence**: optionally refactor jda1.jda to use the new feature, re-verify convergence
5. **Update bootstrap binary** when the compiler changes

This means jda1.jda will lag behind the language — it won't use enums, generics, or methods until those features are battle-tested in user programs.

---

## Test Strategy

Each milestone adds 10-15 conformance tests. Target: 150+ tests by end of Phase 3.

| Milestone | Test Categories |
|-----------|----------------|
| M1 | Type mismatch errors, valid type assignments, pointer types |
| M2 | Inferred `let`, inferred returns, explicit overrides |
| M3 | Simple enums, data enums, match expressions, exhaustiveness |
| M4 | Result creation, `?` operator, error propagation chains |
| M5 | Generic functions, generic structs, monomorphized output |
| M6 | Methods, constructors, `self`/`&self`, method resolution |
| M7 | Ownership moves, compile-time drops, refcount elision |
| M8 | Arena alloc/reset/destroy, arena lifetime checks |
| M9 | Linear type consumption, compiler errors on unconsumed values |

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Type checking breaks self-hosting | High | Add type checks gradually. Run convergence after every change. Keep old code paths as fallback. |
| Monomorphization blows up function table | Medium | Increase table sizes from 256 → 1024. Or switch to dynamic allocation with `alloc`. |
| CTRC dataflow analysis too complex | High | Start with local-scope-only. Single-owner values only. No interprocedural analysis in v1. |
| Enum storage layout complex | Medium | Start with fixed-size unions (max variant size). Optimize later. |
| Method resolution conflicts with field access | Low | Check fields first, then methods. Disallow field/method name collisions. |

---

## Definition of Done

Phase 3 is complete when this program compiles and runs:

```jda
enum Shape {
    Circle(radius: i64)
    Rect(w: i64, h: i64)
}

impl Shape {
    fn area(&self) -> i64 {
        match self {
            Circle(r) => r * r * 3
            Rect(w, h) => w * h
        }
    }
}

fn describe(s: &Shape) -> Result<i64, i64> {
    let a = s.area()
    if a == 0 { ret Result.Err(1) }
    ret Result.Ok(a)
}

fn main() {
    let s = Shape.Circle(10)
    let result = describe(&s)?
    print_int(result)
}
```

Output: `300`

The compiler type-checks it, pattern-matches it, resolves methods, and manages memory — all without C, without a GC, and while still compiling itself.
