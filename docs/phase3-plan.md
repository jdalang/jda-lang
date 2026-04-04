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

### M2: Type Inference

**Why second**: Reduces boilerplate. `let x = 5` should infer `i64` without annotation.

**Tasks**:
1. Infer `let` variable types from right-hand side expression
   - `let x = 5` → `x: i64`
   - `let p = &s` → `p: &StructName`
   - `let r = fn_call()` → type from function return type
2. Infer return types when unambiguous
   - Single-return functions: infer from `ret expr`
   - Multiple returns: require explicit annotation (or all must agree)
3. Propagate inferred types through the type checker (M1)
4. Keep explicit annotations working — inference is optional, never required

**Scope limit**: No Hindley-Milner. Inference flows forward only (left-to-right, top-to-bottom). This is closer to Go/Rust `let` inference than ML-style global inference.

---

### M3: Enums and Pattern Matching

**Why third**: Foundation for `Result<T, E>` (M4) and idiomatic error handling.

**Tasks**:
1. **Enum declarations** — add to lexer, parser, and struct table
   ```jda
   enum Color {
       Red
       Green
       Blue
   }
   ```
   - Simple enums: variants are integer tags (0, 1, 2...)
   - Storage: i64 tag value

2. **Enum with associated data** (tagged unions)
   ```jda
   enum Shape {
       Circle(radius: i64)
       Rect(w: i64, h: i64)
   }
   ```
   - Storage: i64 tag + union of largest variant's fields
   - Compiler computes max variant size for allocation

3. **Pattern matching** — complete the `NODE_MATCH` codegen
   ```jda
   match shape {
       Circle(r) => r * r * 3
       Rect(w, h) => w * h
   }
   ```
   - Lower to: load tag → compare → branch → extract fields
   - Exhaustiveness checking: warn if not all variants covered

4. **Enum in if conditions** (sugar)
   ```jda
   if color == Color.Red { ... }
   ```

**JIR additions**: `OP_TAG_LOAD` (extract tag from enum), `OP_VARIANT_LOAD` (extract field from variant)

**Test plan**: 10+ conformance tests covering simple enums, data enums, nested match, exhaustiveness.

---

### M4: `Result<T, E>` and `?` Operator

**Why fourth**: Depends on enums (M3). This is Jda's error handling story.

**Tasks**:
1. **Result as a built-in enum** (or stdlib enum once generics exist)
   ```jda
   enum Result {
       Ok(val: i64)
       Err(code: i64)
   }
   ```
   - Initially: `Result` holds i64 values only (no generics yet)
   - After M5 (generics): `Result<T, E>` with type parameters

2. **`?` operator** — early return on Err
   ```jda
   fn read_config() -> Result {
       let fd = fs_open("config.txt")?
       let data = fs_read(fd, buf, 1024)?
       ret Result.Ok(data)
   }
   ```
   - Desugars to: `let tmp = expr; match tmp { Err(e) => ret Result.Err(e), Ok(v) => v }`
   - Parser: `?` is a postfix unary operator
   - Codegen: emit match + conditional return

3. **Standard error codes**
   - `ERR_NOT_FOUND = 1`, `ERR_PERMISSION = 2`, `ERR_IO = 3`, etc.
   - Update stdlib functions to return `Result` instead of raw i64

**Test plan**: Result creation, `?` propagation, nested `?`, error bubbling through call chains.

---

### M5: Generics (Monomorphization)

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

### M6: `impl` Blocks and Methods

**Why sixth**: Depends on type checking (M1) and benefits from generics (M5). Methods make structs usable.

**Tasks**:
1. **`impl` block syntax**
   ```jda
   struct Point {
       x: i64
       y: i64
   }

   impl Point {
       fn new(x: i64, y: i64) -> Point {
           let p = Point{}
           p.x = x
           p.y = y
           ret p
       }

       fn distance(&self, other: &Point) -> i64 {
           let dx = other.x - self.x
           let dy = other.y - self.y
           ret dx * dx + dy * dy
       }
   }
   ```

2. **Method dispatch** — desugar to function calls
   - `p.distance(&q)` → `Point_distance(&p, &q)`
   - `&self` is an implicit first parameter
   - Name mangling: `StructName_method_name`

3. **Associated functions** (no self) — constructors
   - `Point.new(3, 4)` → `Point_new(3, 4)`

4. **Method resolution**
   - When parsing `expr.name(args)`, check if `name` is a field (field access) or a method (method call)
   - Lookup in the impl table for the struct type

**Implementation**: Methods are syntactic sugar over functions. No vtable, no dynamic dispatch. This keeps it simple and zero-cost.

---

### M7: Compile-Time Reference Counting (CTRC)

**Why seventh**: Jda's memory safety story. Depends on type checking (M1) and methods (M6) for drop semantics.

**Tasks**:
1. **Ownership tracking in the compiler**
   - Each variable has an owner
   - Assignment transfers ownership (move semantics by default)
   - `let b = a` → `a` is no longer valid

2. **Compile-time refcount insertion**
   - When the compiler can prove a value has exactly one owner → no refcount needed (most cases)
   - When a value is shared (e.g., passed to multiple functions that store it) → insert `rc_inc`/`rc_dec` calls
   - At scope exit → insert `rc_dec` for all owned values

3. **Drop semantics**
   - When refcount hits 0 at compile time → insert deallocation
   - For structs with resources (files, sockets): call a `drop` method if defined in `impl`

4. **JIR additions**: `OP_RC_INC`, `OP_RC_DEC`, `OP_DROP`

5. **Escape analysis**
   - Values that don't escape their scope → stack allocated, no refcount
   - Values that escape (returned, stored in struct) → heap allocated with refcount header

**Design principle**: Most programs should see zero runtime refcount overhead. CTRC is a compile-time optimization pass, not a runtime GC. The compiler statically determines lifetimes wherever possible and only falls back to refcounting for genuinely ambiguous ownership.

**Risk**: This is the hardest milestone. Requires dataflow analysis across function boundaries. Start with local-scope-only analysis, extend to interprocedural later.

---

### M8: Region-Based Allocation (Arenas)

**Why eighth**: Performance complement to CTRC. Hot paths need bulk allocation/deallocation.

**Tasks**:
1. **Arena type**
   ```jda
   let arena = Arena.new(1024 * 1024)  ; 1MB region
   let node = arena.alloc<Node>()
   let buf = arena.alloc_array<i64>(256)
   arena.reset()   ; free everything at once
   arena.destroy()  ; release memory to OS
   ```

2. **Implementation**
   - Arena is a struct with a base pointer, current offset, and capacity
   - `alloc<T>()` bumps the offset by `sizeof(T)`, returns pointer
   - `reset()` sets offset back to 0 (O(1) bulk free)
   - `destroy()` releases pages back to kernel

3. **Integration with CTRC**
   - Arena-allocated values are NOT refcounted (arena owns them)
   - Compiler must track that arena references don't outlive the arena

**This can ship as a stdlib module initially**, then become a language primitive later.

---

### M9: Linear Types for Resource Safety

**Why last**: Depends on CTRC (M7) for ownership tracking. Ensures files, sockets, and other resources are always cleaned up.

**Tasks**:
1. **Linear type annotation**
   ```jda
   struct File {
       fd: i64
       @linear   ; must be consumed — compiler error if dropped without close()
   }
   ```
   - Or: `linear struct File { ... }` syntax

2. **Consumption rules**
   - A linear value must be explicitly consumed (passed to a consuming function)
   - `file.close()` consumes the File — after this, `file` is invalid
   - Compiler error if a linear value goes out of scope without being consumed

3. **Integration with impl blocks**
   ```jda
   impl File {
       fn close(self) {  ; takes ownership, consumes
           syscall(3, self.fd, 0, 0)
       }
   }
   ```
   - `self` (not `&self`) transfers ownership — the method consumes the value

4. **Compiler checks**
   - At every function exit: verify all linear locals were consumed
   - At every branch: verify linear values consumed on all paths

**Design**: Similar to Rust's affine types but explicit opt-in. Only types annotated `@linear` get this treatment. Regular structs remain untracked.

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
