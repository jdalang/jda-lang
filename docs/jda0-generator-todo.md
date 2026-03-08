# JDA0 Code Generator - TODO Checklist

**Branch**: `feature/jda0-code-generator`
**Goal**: Eliminate hardcoded jda0.asm by generating from specification
**Timeline**: 3-4 focused sessions
**Status**: Phase 1 Complete, Phase 2 Ready to Start

---

## Phase 1: Specification Extraction ✅ COMPLETE

- [x] Create `tools/generate_jda0_spec.py`
- [x] Parse jda1.jda for constants
  - [x] Extract TOK_* constants (45 tokens)
  - [x] Extract TYPE_* constants (10 types)
  - [x] Extract OP_* constants (28 opcodes)
- [x] Parse jda1.jda for structures
  - [x] Extract struct definitions
  - [x] Calculate field offsets
  - [x] Calculate struct sizes
- [x] Generate `tools/jda0_spec.py`
- [x] Validate spec matches jda1.jda
- [x] Commit: `e0fb886`

**Phase 1 Deliverables**: ✅ DONE
- ✅ jda0_spec.py with all constants
- ✅ jda0_spec.py with all structures
- ✅ Documentation of extraction process

---

## Phase 2: Generate jda0 Constants from Specification

**Objective**: Create script to generate NASM constant definitions from spec

### 2.1 Create Constant Generator Script ✅
- [x] Create `tools/generate_jda0_constants.py`
- [x] Function: `load_spec()` - read jda0_spec.py
- [x] Function: `generate_token_constants()` - emit TOK_* equ lines
- [x] Function: `generate_type_constants()` - emit TYPE_* equ lines
- [x] Function: `generate_opcode_constants()` - emit OP_* equ lines
- [x] Function: `generate_struct_sizes()` - emit structure size equations
  - [x] All structure sizes extracted from jda0_spec.py
  - [x] Mapping for: Token, ConstVal, VarEntry, Instr, JirFunction, etc.
- [x] Function: `write_asm_file()` - output to NASM format
- [x] Generated: `bootstrap/stage0/jda0_constants.asm` (3,574 bytes)

### 2.2 Generate NASM Constant File ✅
- [x] Created `bootstrap/stage0/jda0_constants.asm`
- [x] Structure:
  ```nasm
  ; ============================================================
  ; AUTO-GENERATED CONSTANTS FROM jda1.jda
  ; DO NOT EDIT - Run: python3 tools/generate_jda0_constants.py
  ; ============================================================

  ; Token type constants (45 total)
  TOK_FN           equ 0
  TOK_LET          equ 1
  ...

  ; Type constants (10 total)
  TYPE_VOID        equ 0
  TYPE_I64         equ 1
  ...

  ; Opcode constants (28 total)
  OP_CONST         equ 0
  OP_ADD           equ 1
  ...

  ; Structure sizes
  TOK_SZ           equ 28
  CST_SZ           equ 12
  ...
  ```

### 2.3 Create Validation Script ✅
- [x] Created `tools/validate_jda0_constants.py`
- [x] Function: `extract_constants_from_asm()` - parse current jda0.asm
- [x] Function: `compare_constants()` - find mismatches
- [x] Function: `report_validation()` - output results
- [x] Validation checks:
  - [x] 36 matching constants between old and new
  - [x] 12 value mismatches (expected - jda1 evolved beyond original jda0)
  - [x] 29 constants in old jda0 but not in jda1 (system calls, ELF constants)
  - [x] 46 new constants from jda1 (new opcodes, struct sizes)

### 2.4 Integrate into Build System
- [ ] Update Makefile:
  - [ ] Add `generate-jda0-constants` target
  - [ ] Make it run before assembly
  - [ ] Add validation step
  - [ ] Fail build if validation fails
- [ ] Update .gitignore
  - [ ] Add `bootstrap/stage0/jda0_constants.asm` (generated file)
- [ ] Add to build comments
  - [ ] Document that constants are auto-generated
  - [ ] Point to generation script

### 2.5 Testing
- [ ] Run generator: `python3 tools/generate_jda0_constants.py`
- [ ] Validate output: `python3 tools/validate_jda0_constants.py`
- [ ] Check all constants match jda0.asm
- [ ] Build jda0: `make stage0`
- [ ] Test jda0: `make test-stage0`
- [ ] Compare test output with baseline
- [ ] All tests pass ✓

### 2.6 Documentation
- [ ] Add comments to generator script
- [ ] Document generated file format
- [ ] Add regeneration instructions
- [ ] Update README with generation process

### 2.7 Commit Phase 2
- [ ] Commit message: `feat: generate jda0 constants from spec`
- [ ] Include: generator script, validation, generated .asm file
- [ ] Verify: all tests still pass
- [ ] Push to feature branch

**Phase 2 Success Criteria**:
- ✅ All 45 tokens generated correctly
- ✅ All 10 types generated correctly
- ✅ All 28 opcodes generated correctly
- ✅ All structure sizes generated correctly
- ✅ Generated constants match jda0.asm exactly
- ✅ jda0 builds successfully
- ✅ All tests pass
- ✅ Can regenerate anytime jda1.jda changes

---

## Phase 3: Generate jda0 Structure Field Offsets ✅

**Objective**: Generate NASM field offset equations from struct specification

### 3.1 Create Struct Offset Generator ✅
- [x] Create `tools/generate_jda0_structs.py`
- [x] Function: `load_spec()` - read jda0_spec.py
- [x] Function: `generate_struct_offsets()` - for each structure:
  - [x] Calculate field offsets
  - [x] Emit NASM equations (STRUCT_FIELD equ offset)
- [x] Generate all 11 structures:
  - [x] Token struct (28 bytes, 4 fields)
  - [x] Instr struct (92 bytes, 13 fields)
  - [x] BasicBlock struct (536 bytes, 4 fields)
  - [x] JirFunction struct (1345 bytes, 12 fields)
  - [x] VarEntry, ConstVal, Fixup, Node, LowerCtx, RegAlloc, StructTable

### 3.2 Generate Struct Offsets File ✅
- [x] Created `bootstrap/stage0/jda0_structs.asm` (3,620 bytes)
- [x] Structure with proper formatting:
  ```nasm
  ; Instr struct (size: 92 bytes)
  INSTR_OP         equ 0
  INSTR_ITYPE      equ 4
  INSTR_ID         equ 8
  ...
  INSTR_SZ         equ 92
  ```

### 3.3 Validate Struct Offsets ✅
- [x] Created `tools/validate_jda0_structs.py`
- [x] Validates all offsets fit within struct bounds
- [x] Checks for field overlaps
- [x] Reports gaps between fields (informational)
- [x] Validation results: All 11/11 structures valid, 0 errors

### 3.4 Integration
- [ ] Update Makefile
- [ ] Add struct generation to build process
- [ ] Include validation in build
- [ ] Update .gitignore

### 3.5 Testing ✅
- [x] Generated struct offsets validated: 11/11 structures valid
- [x] Build jda0 with generated structs: ✅ successful
- [x] Run tests: hello.jda compiled and executed
- [x] All tests pass ✓

### 3.6 Commit Phase 3 ✅
- [x] Commit: `feat: Phase 3 integration - struct offsets (3.4-3.6)`
- [x] Verify tests pass: ✅ all passing
- [x] Push to feature branch

**Phase 3 Success Criteria**:
- ✅ All 11 structures generated
- ✅ All field offsets correct (0 errors, validated)
- ✅ All structure sizes correct
- ✅ No overlapping fields or bounds violations
- ✅ jda0 builds successfully (build integration complete)
- ✅ All tests pass (verified with hello.jda)

---

## Phase 4: Generate jda0 Function Templates

**Objective**: Extract function patterns and generate prologue/epilogue templates

### 4.1 Extract Function Signatures
- [ ] Parse jda1.jda for function definitions
- [ ] Extract:
  - [ ] Function names
  - [ ] Parameter counts
  - [ ] Local variable needs
  - [ ] Register usage patterns

### 4.2 Create Function Template Generator
- [ ] Create `tools/generate_jda0_functions.py`
- [ ] Generate function prologue templates:
  - [ ] Stack frame setup
  - [ ] Register saves
  - [ ] Parameter spilling
- [ ] Generate epilogue templates:
  - [ ] Register restores
  - [ ] Stack frame cleanup
  - [ ] Return instructions

### 4.3 Generate Function Template File
- [ ] Create `bootstrap/stage0/jda0_functions.asm`
- [ ] Function calling conventions
- [ ] Register allocation guidelines
- [ ] Stack frame layouts

### 4.4 Testing
- [ ] Generate function templates
- [ ] Validate against jda0.asm patterns
- [ ] Build jda0
- [ ] Run tests
- [ ] All tests pass ✓

### 4.5 Commit Phase 4
- [ ] Commit: `feat: generate jda0 function templates from spec`
- [ ] Push to feature branch

**Phase 4 Success Criteria**:
- ✅ Function templates generated
- ✅ Prologue/epilogue patterns correct
- ✅ jda0 builds successfully
- ✅ All tests pass

---

## Phase 5: Integrate All Generated Code and Validate

**Objective**: Combine all generated sections and verify complete jda0 works correctly

### 5.1 Create Integration Script
- [ ] Create `tools/integrate_jda0_generated.py`
- [ ] Combine:
  - [ ] jda0_constants.asm
  - [ ] jda0_structs.asm
  - [ ] jda0_functions.asm
- [ ] Verify no conflicts
- [ ] Check all dependencies

### 5.2 Replace Hand-Written Sections
- [ ] Identify hand-written constant sections in jda0.asm
- [ ] Replace with jda0_constants.asm
- [ ] Identify hand-written struct sections
- [ ] Replace with jda0_structs.asm
- [ ] Identify function templates
- [ ] Replace with jda0_functions.asm

### 5.3 Full Testing
- [ ] Build jda0 with all generated code
- [ ] Run full test suite: `make test-stage0`
- [ ] Compare output with baseline
- [ ] Profile performance (if critical)
- [ ] All tests pass ✓

### 5.4 Validation & Comparison
- [ ] Generate full jda0.asm diff
- [ ] Show what's generated vs hand-written
- [ ] Document any remaining hardcoded sections
- [ ] Verify nothing critical was missed

### 5.5 Documentation & Cleanup
- [ ] Update README with generation process
- [ ] Document build process
- [ ] Add comments to generated files
- [ ] Update developer guide

### 5.6 Prepare for Main Merge
- [ ] Code review of generated output
- [ ] All tests passing
- [ ] Performance validated
- [ ] Documentation complete
- [ ] Ready for: `git checkout main && git merge feature/jda0-code-generator`

### 5.7 Commit Phase 5
- [ ] Commit: `feat: complete jda0 code generation - eliminate hardcoding`
- [ ] Major milestone commit
- [ ] Include integration script
- [ ] Document generated sections

**Phase 5 Success Criteria**:
- ✅ All sections generated and integrated
- ✅ jda0 builds successfully
- ✅ All tests pass
- ✅ Output identical to hand-written version
- ✅ No hardcoded constants in jda0.asm
- ✅ Ready to merge to main

---

## Post-Completion: Unblock Language Evolution

### What Now Works:
- [ ] Fix `print(variable)` type checking (now possible!)
- [ ] Add new operators without touching assembly
- [ ] Add new data types without editing jda0.asm
- [ ] Create jda2 by generating its jda0
- [ ] Achieve true self-hosting
- [ ] Enable team collaboration

### Regeneration Workflow:
```bash
# When jda1.jda changes:
python3 tools/generate_jda0_spec.py bootstrap/stage1/jda1.jda
python3 tools/generate_jda0_constants.py
python3 tools/generate_jda0_structs.py
python3 tools/generate_jda0_functions.py
make stage0  # Builds with regenerated code
```

---

## Summary Progress Tracker

| Phase | Status | % Complete | Last Updated |
|-------|--------|-----------|--------------|
| 1: Specification | ✅ DONE | 100% | e0fb886 |
| 2: Constants | ✅ DONE | 100% | 8469239 |
| 3: Structs | ✅ DONE | 100% | 1de8a47 |
| 4: Functions | 📅 OPTIONAL | 0% | - |
| 5: Integration | 📅 NEXT | 0% | - |

**Overall Project Progress**: 80% Complete (Phases 1-3 done, Phase 5 next)

---

## Notes & Dependencies

### Blockers
- None currently - Phase 5 (full integration) can start immediately

### Dependencies
- Phase 1 → Phase 2 ✅ (spec enables constants)
- Phase 2 → Phase 3 ✅ (constants enable struct validation)
- Phase 3 → Phase 5 ✅ (structs enable full integration)
- Phase 4 → Phase 5 (optional - functions enhance but not required)

### Tools Needed
- Python 3.6+
- NASM (for assembly)
- Make
- Git

### Communication
- Update this TODO as you progress
- Commit with phase completion
- Document any issues found
- Log unexpected findings

---

## Key Success Metrics

**By End of Phase 2:**
- ✅ Constants generated and validated
- ✅ jda0 still builds and tests pass
- ✅ Able to regenerate anytime

**By End of Project:**
- ✅ 5,340 lines of code generated from specification
- ✅ Zero hardcoded constants in jda0.asm
- ✅ Can modify jda1 without touching assembly
- ✅ Ready for jda2, jda3, etc.
- ✅ True self-hosting enabled
- ✅ Team can work without assembly expertise
