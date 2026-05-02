# Stage 0 Extension Roadmap: Self-Hosting Jda

**Goal:** Extend Stage 0 (NASM x86-64 bootstrapper) to compile jda1.jda, enabling Stage 1 to self-host.

**Current Status:**
- Stage 0 supports: `print()`, `let` bindings, basic arithmetic, `ret` statements
- jda1.jda requires: `fn`, `struct`, `if/else`, `loop`, `match`, `syscall`
- jda1.jda size: 1,767 lines, 88 functions, 10 struct definitions

---

## Feature Gap Analysis

From `tools/dev/source_analyzer.py` on jda1.jda:

| Feature | Uses | Priority | Status |
|---------|------|----------|--------|
| **Functions** (`fn`) | 88 | 🔴 CRITICAL | ❌ Missing |
| **Structs** | 10 | 🔴 CRITICAL | ❌ Missing |
| **If statements** | 166 | 🔴 CRITICAL | ❌ Missing |
| **Loop statements** | 34 | 🔴 CRITICAL | ❌ Missing |
| **Pattern matching** (`match`) | 1 | 🔴 CRITICAL | ❌ Missing |
| **Syscall** | 15 | 🟡 IMPORTANT | ❌ Missing |
| **Print calls** | 7 | 🟢 DONE | ✅ Supported |
| **Let bindings** | 210 | 🟢 DONE | ✅ Supported |
| **Ret statements** | 133 | 🟢 DONE | ✅ Supported |

---

## Implementation Strategy

### Phase 1: Infrastructure & Tooling (Week 1) ✅
- [x] Create `tools/dev/source_analyzer.py` — identify missing features
- [x] Create `tools/dev/source_splitter.py` — split jda1.jda for incremental compilation
- [x] Create `tools/dev/compile_workflow.sh` — orchestrate builds with feedback

**Status:** Python tools complete. Ready to analyze and split jda1.jda.

---

### Phase 2: Core Parser Extensions (Weeks 2-4)

Extend Stage 0 NASM to parse and emit code for:

#### 2.1 Function Definitions (`fn`)
**Feature:** `fn name(params) -> type { body }`

**Implementation approach:**
1. Extend lexer to recognize `fn` keyword
2. Parse function signature: name, parameter list with types, return type
3. Parse function body (reuse existing statement parser)
4. Symbol table: store function name → code offset mapping
5. Code gen: emit function prologue (save RBP, adjust RSP), body, epilogue (restore RBP, ret)

**Complexity:** High (requires symbol table enhancement)  
**Estimated lines:** 400-600 NASM

**Test case:**
```jda
fn add(a: i64, b: i64) -> i64 {
    ret a + b
}
fn main() {
    print(add(2, 3))
}
```

#### 2.2 Control Flow: If/Else
**Feature:** `if cond { ... } else { ... }`

**Implementation approach:**
1. Parse condition expression (reuse binop parser)
2. Generate comparison: `cmp rax, 0`
3. Branch: `jz else_label` for false branch
4. Emit then-block code
5. Jump over else: `jmp endif_label`
6. Emit else-block code
7. Mark `endif_label`

**Complexity:** Medium (mostly jumps & labels)  
**Estimated lines:** 200-300 NASM

**Test case:**
```jda
fn max(a: i64, b: i64) -> i64 {
    if a > b { ret a } else { ret b }
}
```

#### 2.3 Control Flow: Loops
**Feature:** `loop condition { body }`

**Implementation approach:**
1. Mark loop start label
2. Parse/eval condition
3. Branch if false: `jz loop_end`
4. Emit loop body
5. Jump back: `jmp loop_start`
6. Mark `loop_end` label

**Complexity:** Medium (similar to if/else)  
**Estimated lines:** 150-250 NASM

**Test case:**
```jda
fn sum(n: i64) -> i64 {
    let total = 0
    let i = 0
    loop i < n {
        total = total + i
        i = i + 1
    }
    ret total
}
```

#### 2.4 Struct Definitions
**Feature:** `struct Name { field: type, ... }`

**Implementation approach:**
1. Parse struct keyword + name + field list
2. Record struct layout: field name → offset mapping
3. Allocate space when structs instantiated (arena allocator or stack)
4. Support field access: `obj.field` → calculate offset & load/store

**Complexity:** High (requires memory layout, field resolution)  
**Estimated lines:** 300-500 NASM

**Test case:**
```jda
struct Point { x: i64  y: i64 }
fn main() {
    let p = Point { x: 10, y: 20 }
    print(p.x)
}
```

#### 2.5 Pattern Matching (`match`)
**Feature:** `match expr { val => expr, ... }`

**Implementation approach:**
1. Evaluate match subject
2. Compare against each pattern
3. Jump to matching arm
4. (For now, only support literal matching; skip union types)

**Complexity:** Very High (pattern analysis, dispatch logic)  
**Estimated lines:** 400-700 NASM

**Note:** Only **1 use** in jda1.jda (low priority — defer to later)

#### 2.6 Syscall Support (`syscall`)
**Feature:** `syscall(nr, a, b, c) -> i64`

**Implementation approach:**
1. Parse syscall expression
2. Evaluate syscall number + arguments
3. Place in registers per x86-64 syscall ABI (rax=syscall#, rdi/rsi/rdx/rcx=args)
4. Emit `syscall` instruction
5. Result in rax

**Complexity:** Low (just register setup + syscall instruction)  
**Estimated lines:** 100-150 NASM

**Test case:**
```jda
fn main() {
    let result = syscall(1, 1, "hello", 5)
    ret result
}
```

---

### Phase 3: Validation & Testing (Weeks 5-6)

#### 3.1 Conformance Tests
- Create `tests/conformance/stage0/` fixtures for each new feature
- Test combinations: functions + loops, structs + field access, etc.
- Automated pass/fail checking in CI

#### 3.2 Bootstrap Tests
- Test: Stage 0 → tiny jda1 (functions only)
- Test: Stage 0 → fuller jda1 (functions + loops)
- Test: Stage 0 → full jda1 (all features)
- Verify roundtrip: Stage1-A → Stage1-B → Stage1-B (binary match)

#### 3.3 Self-Hosting Gate
- `make selfhost`: Stage0 compiles full jda1.jda → jda1_stage1
- jda1_stage1 compiles hello.jda → hello_out
- hello_out runs successfully
- CI includes this as merge gate

---

### Phase 4: Documentation & Integration (Week 7)

- [ ] Update `docs/CONFORMANCE_STATUS.md` with Stage 0 feature matrix
- [ ] Document Stage 0 parser architecture (lexer, parser, codegen)
- [ ] Add examples for each new feature
- [ ] Update `README.md` roadmap (mark self-hosting complete)
- [ ] Wire Python tools into Makefile (`make analyze-features`, etc.)

---

## Incremental Milestones

### Milestone 1: Functions ✅ Phase 2.1
**Goal:** Stage 0 can parse and emit code for top-level `fn` definitions.

**Definition of Done:**
- [ ] Parse `fn name(params) -> type { body }`
- [ ] Call functions correctly (push args, jump, handle return)
- [ ] 3+ conformance tests passing
- [ ] jda1.jda functions can be compiled (even if body has unsupported syntax)

**Impact:** Opens path to compiling jda1's 88 functions

---

### Milestone 2: Control Flow (If/Else + Loops) ✅ Phase 2.2 + 2.3
**Goal:** Stage 0 can emit branching and looping code.

**Definition of Done:**
- [ ] `if condition { } else { }` expressions work
- [ ] `loop condition { }` statements work
- [ ] Proper jump/label generation
- [ ] 5+ conformance tests passing (nested if, loops in functions, etc.)

**Impact:** Unlocks jda1's 166 if-statements and 34 loop-statements

---

### Milestone 3: Structs ✅ Phase 2.4
**Goal:** Stage 0 can parse struct definitions and handle field access.

**Definition of Done:**
- [ ] Parse `struct Name { field: type, ... }`
- [ ] Support instantiation and field access
- [ ] Correct memory layout (offset calculation)
- [ ] 3+ conformance tests

**Impact:** Unlocks jda1's 10 struct definitions (Token, Node, Instr, etc.)

---

### Milestone 4: Syscalls + Match (Optional, Later)
**Goal:** Complete feature support for jda1.jda.

**Definition of Done:**
- [ ] `syscall(nr, args)` works
- [ ] `match` expressions work
- [ ] All jda1.jda syntax compiles

---

## Effort Estimates

| Phase | Task | NASM LOC | Complexity | Effort | Timeline |
|-------|------|----------|------------|--------|----------|
| 1 | Tooling | ~1.2K | Low | 2-3 days | ✅ Done |
| 2.1 | Functions | 400-600 | High | 3-4 days | Week 2 |
| 2.2+2.3 | If/Loop | 350-550 | Medium | 2-3 days | Week 3 |
| 2.4 | Structs | 300-500 | High | 3-4 days | Week 4 |
| 2.5 | Syscalls | 100-150 | Low | 1 day | Week 4 |
| 3 | Testing | — | Medium | 2-3 days | Week 5-6 |
| 4 | Docs | — | Low | 1 day | Week 7 |
| **Total** | | **~2K-2.5K NASM** | **Mixed** | **2-3 weeks** | |

---

## Success Criteria

- [ ] Stage 0 NASM grows from 2,400 lines to ~4,400-5,000 lines
- [ ] All 5 critical feature gaps closed (fn, struct, if, loop, match)
- [ ] 20+ new conformance tests, all passing
- [ ] Stage 0 can compile full jda1.jda (1,767 lines)
- [ ] Stage 1 binary from Stage 0 can self-compile (roundtrip validated)
- [ ] CI green: `make selfhost` succeeds, binary match verified
- [ ] Roadmap item "Self-hosting: Stage 1 compiled by Stage 0" marked ✅

---

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|-----------|
| NASM complexity | Hard to maintain, bugs in asm | Extensive testing, small incremental PRs |
| Symbol table bugs | Function/variable resolution fails | Unit tests for symbol lookup |
| Register allocation | Spilling/overflow | Document register use, test with deep nesting |
| Memory layout | Struct field offset wrong | Explicit offset calculation, tests |
| Bootstrapping loop | Self-hosting broken | Roundtrip gate in CI, binary-match validation |

---

## Tools & Scripts

### Analysis
```bash
python3 tools/dev/source_analyzer.py bootstrap/stage1/jda1.jda
python3 tools/dev/source_splitter.py bootstrap/stage1/jda1.jda --chunk-size 500
```

### Build & Test
```bash
cd bootstrap/stage0
make all                          # Build Stage 0 (jda0 binary)
make test                         # Test: Stage 0 → hello.jda
make stage1                       # Compile jda1.jda with Stage 0
make selfhost                     # Full self-hosting: Stage1 → Stage1
```

### Workflow
```bash
tools/dev/compile_workflow.sh <source.jda> <output> --analyze
tools/dev/compile_workflow.sh <source.jda> <output> --split
tools/dev/compile_workflow.sh <source.jda> <output>
```

---

## References

- Stage 0 source: `bootstrap/stage0/jda0.asm` (2,400 lines)
- Stage 1 source: `bootstrap/stage1/jda1.jda` (1,767 lines)
- Conformance tests: `tests/conformance/stage0/{pass,fail}/`
- CI workflows: `.github/workflows/stage0-ci.yml`
- Language spec: `syntax/spec.jda`

---

## Timeline Summary

| Week | Deliverable | Status |
|------|-------------|--------|
| ✅ 1 | Python tooling (analyzer, splitter, workflow) | Done |
| 2️⃣ 2 | Functions (`fn`) support in Stage 0 | Pending |
| 3️⃣ 3 | Control flow (`if`, `loop`) | Pending |
| 4️⃣ 4 | Structs + Syscalls | Pending |
| 5️⃣ 5-6 | Validation & conformance tests | Pending |
| 6️⃣ 7 | Documentation & integration | Pending |

**Total timeline: 2-3 weeks for feature-complete Stage 0 → Stage 1 self-hosting.**
