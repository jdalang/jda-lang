# JDA0 Code Generator - Implementation Plan

**Branch**: `feature/jda0-code-generator`
**Goal**: Transform jda0 from 5,340 lines of hand-written assembly to generated code
**Timeline**: 3-4 focused sessions
**Impact**: Unblocks language evolution and enables true self-hosting

---

## Phase Overview

### Phase 1: Specification Extraction ✅ DONE
- Extract constants from jda1.jda → `jda0_spec.py`
- Extract struct definitions with offsets
- Commit: e0fb886

### Phase 2: Constant Generation (THIS PHASE)
**Goal**: Generate jda0 constant sections from specification
**Files to create**:
- `tools/generate_jda0_constants.py` - Generate constant tables
- `bootstrap/stage0/jda0_constants.asm` - Generated constant definitions

**Steps**:
1. Read `jda0_spec.py`
2. Generate NASM format:
   ```nasm
   ; Auto-generated from jda1.jda
   TOK_FN           equ 0
   TOK_LET          equ 1
   ...
   ```
3. Generate structure size equations:
   ```nasm
   ; Structure sizes
   TOK_SZ           equ 32
   FN_SZ            equ 288
   ```
4. Test: Verify generated constants match current jda0.asm values

**Deliverables**:
- Script that generates constant sections
- Validates against current jda0.asm
- Shows diff of any changes

---

### Phase 3: Structure Field Offset Generation
**Goal**: Generate all struct field offset equations
**Files**:
- `tools/generate_jda0_structs.py`
- `bootstrap/stage0/jda0_structs.asm` - Generated struct layouts

**Steps**:
1. Parse `jda0_spec.py` structures
2. Generate field offset equations:
   ```nasm
   ; Instr struct fields
   INSTR_OP         equ 0
   INSTR_ITYPE      equ 8
   INSTR_OPERAND0   equ 16
   ...
   ```
3. Generate structure sizes
4. Validate against hand-written jda0.asm

**Deliverables**:
- Complete struct offset generation
- Size validation
- Clear diff showing any mismatches

---

### Phase 4: Function Signature & Layout Generation
**Goal**: Generate function prologue/epilogue templates
**Files**:
- `tools/generate_jda0_functions.py`
- Generated function templates

**Steps**:
1. Extract function signatures from jda1.jda
2. Generate stack frame calculations
3. Generate register save/restore templates
4. Validate calling conventions

---

### Phase 5: Integration & Validation
**Goal**: Verify generated jda0 matches current behavior
**Steps**:
1. Combine all generated sections
2. Run jda0 tests
3. Compare with hand-written jda0.asm
4. Fix any discrepancies

---

## Implementation Details

### Phase 2 Detailed Steps

#### Step 1: Create Generator Script
```python
# tools/generate_jda0_constants.py
def generate_constants(spec):
    output = "; Auto-generated from jda1.jda\n"
    for name, value in spec.items():
        output += f"{name:20} equ {value}\n"
    return output
```

#### Step 2: Output Format
```nasm
; ============================================================
; AUTO-GENERATED CONSTANTS FROM jda1.jda
; DO NOT EDIT - Run: python3 tools/generate_jda0_constants.py
; ============================================================

; Token type constants
TOK_FN           equ 0
TOK_LET          equ 1
...

; Type constants
TYPE_VOID        equ 0
TYPE_I64         equ 1
...

; Opcode constants
OP_CONST         equ 0
OP_ADD           equ 1
...
```

#### Step 3: Validation Script
```python
# Validate generated constants match jda0.asm
def validate_constants(generated, current_jda0_asm):
    for name, value in generated.items():
        if current_jda0_asm[name] != value:
            print(f"MISMATCH: {name} = {value} vs {current_jda0_asm[name]}")
```

#### Step 4: Integration
- Add to Makefile: `generate-jda0-constants` target
- Make it part of build: `make stage0` regenerates constants
- Add safety check: fail if generated doesn't match current jda0

---

## Testing Strategy

### Unit Tests (Per Phase)
- Phase 2: Constant generation matches jda0.asm
- Phase 3: Struct offsets are correct
- Phase 4: Function layouts work
- Phase 5: Full integration test

### Integration Test
```bash
# Build jda0 with generated constants
make stage0
# Run all tests
make test-stage0
# Compare output with baseline
```

### Validation Checklist
- [ ] Generated constants match hand-written
- [ ] Struct sizes are correct
- [ ] Field offsets are accurate
- [ ] jda0 compiles jda1.jda successfully
- [ ] jda1 produces same output as hand-written version
- [ ] All tests pass

---

## Success Criteria

✅ Phase 2 Success:
- Constants generated correctly
- All values match jda0.asm
- Generation script is reliable
- Can regenerate anytime jda1.jda changes

✅ Full Project Success:
- All 5,340 lines of jda0.asm generated from spec
- No hardcoding required
- Can add features to jda1 without touching assembly
- Build process: `make stage0` regenerates everything
- Ready for jda2, jda3, etc.

---

## Risks & Mitigation

| Risk | Mitigation |
|------|-----------|
| Generated code has bugs | Validate against current jda0.asm line-by-line |
| Generator is incomplete | Start with constants (easy), add complexity gradually |
| Performance regression | Profile before/after, optimize if needed |
| Team confusion | Clear docs, automated generation in build |

---

## Commit Strategy

Per phase:
- Phase 2: `feat: generate jda0 constants from spec`
- Phase 3: `feat: generate jda0 struct layouts from spec`
- Phase 4: `feat: generate jda0 function templates from spec`
- Phase 5: `feat: complete jda0 code generation - eliminate hardcoding`

Merge to main only after:
- All tests pass
- Performance verified
- Documentation complete

---

## Future Benefits

Once this is done:

1. **Add feature to jda1** → Regenerate spec → Done ✅
2. **Fix print(variable)** → Works immediately ✅
3. **Create jda2** → Generate its jda0 ✅
4. **True self-hosting** → jda1 compiles jda1 ✅
5. **Team collaboration** → No assembly expertise needed ✅

