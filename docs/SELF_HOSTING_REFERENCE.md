# Self-Hosting Jda Compiler: Complete Reference

## Overview
Phase 1 (Infrastructure & Planning) is complete. This document serves as the master reference for the self-hosting initiative: extending Stage 0 (NASM x86-64 bootstrapper) to compile Stage 1 (jda1.jda), achieving compiler self-hosting.

---

## Quick Links

### For Developers
- **Roadmap:** `docs/STAGE0_EXTENSION_ROADMAP.md` — Full 7-week implementation plan
- **Analysis:** `make analyze-features` — See what Stage 0 needs to compile jda1.jda
- **Workflow:** `tools/dev/compile_workflow.sh` — Try compiling with analysis

### For Project Management
- **Session Plan:** `.copilot/session-state/.../plan.md` — Detailed workplan with checkboxes
- **Session Summary:** `.copilot/session-state/.../SESSION_SUMMARY.md` — Full recap
- **Status:** Phase 1 ✅ DONE, Phase 2 pending (2-3 weeks)

### For CI/CD Integration
- **Analysis Tool:** `tools/dev/source_analyzer.py` — Identify feature gaps (JSON output available)
- **Splitter Tool:** `tools/dev/source_splitter.py` — Decompose sources for incremental builds
- **Makefile Targets:** `make analyze-features`, `make split-source`, `make compile-demo`

---

## Architecture

### Current State (Before Self-Hosting)
```
Stage 0 (jda0.asm - 2,400 lines NASM)
  ↓ (can only compile: print, let, ret, basic arithmetic)
Hello.jda ✅
  
jda1.jda (Stage 1 - 1,767 lines, needs: fn, struct, if, loop, match, syscall)
  ✗ Cannot compile with current Stage 0 (missing 5 critical feature types)
```

### Target State (After Self-Hosting)
```
Stage 0 (jda0.asm - ~4,400-5,000 lines NASM after extensions)
  ↓ (can compile: print, let, ret, arithmetic, fn, struct, if, loop, match, syscall)
jda1.jda ✅
  ↓ (compiled by Stage 0 → jda1 binary)
jda1 (Stage 1 self-hosted) ✅
  ↓ (can compile: all Jda features)
jda1.jda (self-hosted) ✅
```

### Feature Gap Analysis
| Feature | Uses | Priority | Status |
|---------|------|----------|--------|
| **Functions (fn)** | 88 | 🔴 Critical | ❌ Missing |
| **Structs** | 10 | 🔴 Critical | ❌ Missing |
| **If statements** | 166 | 🔴 Critical | ❌ Missing |
| **Loop statements** | 34 | 🔴 Critical | ❌ Missing |
| **Pattern matching (match)** | 1 | 🔴 Critical | ❌ Missing |
| **Syscalls** | 15 | 🟡 Important | ❌ Missing |
| **Print calls** | 7 | 🟢 Done | ✅ Supported |
| **Let bindings** | 210 | 🟢 Done | ✅ Supported |
| **Return statements** | 133 | 🟢 Done | ✅ Supported |

---

## Tools & Scripts

### 1. Source Analyzer (`tools/dev/source_analyzer.py`)
**Purpose:** Identifies what features a Jda source file needs and what Stage 0 lacks.

**Key Features:**
- Parses struct and function definitions
- Tracks keyword frequencies
- Identifies critical gaps blocking self-hosting
- Generates feature inventory with line references

**Usage:**
```bash
# Quick analysis
make analyze-features

# Detailed analysis
python3 tools/dev/source_analyzer.py bootstrap/stage1/jda1.jda

# JSON output (for CI integration)
python3 tools/dev/source_analyzer.py bootstrap/stage1/jda1.jda --json
```

**Output on jda1.jda:**
- 88 function definitions
- 10 struct definitions
- 166 if statements
- 34 loop statements
- 5 critical feature gaps

### 2. Source Splitter (`tools/dev/source_splitter.py`)
**Purpose:** Decomposes large source files into compilable chunks while preserving dependencies.

**Strategies:**
- **By-lines:** Simple chunking (e.g., 5 chunks for jda1.jda)
- **By-functions:** Function-level chunking (e.g., 89 chunks: 1 header + 88 functions)

**Usage:**
```bash
# Show decomposition strategies
make split-source

# Detailed analysis
python3 tools/dev/source_splitter.py bootstrap/stage1/jda1.jda
```

**Output:**
- Struct/function location mapping
- Dependency analysis (which functions call which)
- Chunk size estimates
- Recommendations for incremental compilation

### 3. Compilation Workflow (`tools/dev/compile_workflow.sh`)
**Purpose:** Orchestrates end-to-end compilation with analysis and validation.

**Modes:**
- `--analyze` — Feature analysis only (no compilation)
- `--split` — Decomposition analysis
- Default — Full compilation attempt with feedback

**Usage:**
```bash
# Demo mode (quick analysis)
make compile-demo

# Analyze jda1.jda
bash tools/dev/compile_workflow.sh bootstrap/stage1/jda1.jda /tmp/jda1 --analyze

# Test compilation of hello.jda
bash tools/dev/compile_workflow.sh examples/hello.jda /tmp/hello

# Show split strategies
bash tools/dev/compile_workflow.sh bootstrap/stage1/jda1.jda /tmp/jda1 --split
```

**Output:**
- Feature inventory
- Stage 0 capability summary
- Compilation attempt (if no --analyze flag)
- Binary validation and self-hosting detection

---

## Implementation Phases

### Phase 1: Infrastructure & Analysis ✅ COMPLETE

**What was delivered:**
- Python analysis and splitting tools
- Compilation workflow orchestration
- Makefile integration (3 new targets)
- Comprehensive 7-week roadmap
- Feature gap analysis

**Status:** All deliverables complete, tools tested and integrated

### Phase 2: Functions (fn keyword) — 2 weeks
**Impact:** 88 function definitions in jda1.jda become compilable

**What needs to be done:**
1. Extend Stage 0 lexer to recognize `fn` keyword
2. Parse function signatures: name, parameters, return type
3. Parse function bodies (reuse existing statement parser)
4. Emit function prologue (save RBP, adjust RSP)
5. Emit function epilogue (restore RBP, ret)
6. Implement function call mechanism

**Effort:** 400-600 lines NASM  
**Test:** 3+ conformance tests, e.g., simple add function, recursive factorial

### Phase 3: Control Flow (if/loop) — 1 week
**Impact:** 200 control flow statements in jda1.jda become compilable

**What needs to be done:**
1. Parse if/else conditionals
2. Generate comparison and conditional jumps
3. Parse loop statements
4. Generate loop labels and backward jumps
5. Support nested control flow

**Effort:** 350-550 lines NASM  
**Test:** 5+ conformance tests for nested loops, conditional logic

### Phase 4: Structs & Syscalls — 1 week
**Impact:** 10 struct types and 15 syscalls become compilable

**Struct support:**
1. Parse struct definitions
2. Calculate field offsets
3. Support instantiation and field access

**Syscall support:**
1. Parse syscall expressions
2. Set up registers per x86-64 syscall ABI
3. Emit syscall instruction

**Effort:** 500-800 lines NASM  
**Test:** 3+ struct/field tests, 2+ syscall tests

### Phase 5: Testing & Validation — 1.5 weeks

**What needs to be done:**
1. Build comprehensive conformance suite (20+ tests)
2. Implement bootstrap validation tests
3. Roundtrip validation (Stage0→Stage1→Stage1 binary match)
4. CI gate implementation

**Effort:** Testing infrastructure and 20+ test cases

### Phase 6: Documentation & Integration — 0.5 weeks

**What needs to be done:**
1. Update CONFORMANCE_STATUS.md
2. Document Stage 0 feature matrix
3. Update README.md roadmap
4. Finalize CI setup

**Result:** Self-hosting milestone marked as complete

---

## Success Metrics

### Phase 1 (✅ Complete)
- [x] Python tools analyze jda1.jda correctly (88 fn, 10 struct, 166 if, 34 loop)
- [x] Source splitter generates valid chunk decompositions
- [x] Workflow script provides actionable feedback
- [x] Tools integrated into Makefile
- [x] Comprehensive 7-week roadmap created
- [x] No new external dependencies

### Phase 2-4 (Pending)
- [ ] Stage 0 NASM extended with all 6 feature types
- [ ] All new features have passing conformance tests
- [ ] Stage 0 can compile full jda1.jda (1,767 lines)

### Phase 5-6 (Final)
- [ ] Stage 1 binary (compiled by Stage 0) can self-compile
- [ ] Roundtrip validation: Stage0→Stage1→Stage1 (binary match)
- [ ] CI green: `make selfhost` succeeds
- [ ] Roadmap item "Self-hosting: Stage 1 compiled by Stage 0" marked ✅

---

## Commands & Recipes

### Quick Start (5 minutes)
```bash
# See what needs to be implemented
make analyze-features

# Understand decomposition strategy
make split-source

# Run workflow demo
make compile-demo
```

### Detailed Analysis
```bash
# Full feature analysis with line numbers
python3 tools/dev/source_analyzer.py bootstrap/stage1/jda1.jda

# JSON output for scripting
python3 tools/dev/source_analyzer.py bootstrap/stage1/jda1.jda --json

# Split strategy analysis
python3 tools/dev/source_splitter.py bootstrap/stage1/jda1.jda

# Workflow with split analysis
bash tools/dev/compile_workflow.sh bootstrap/stage1/jda1.jda /tmp/out --split
```

### Building & Testing (existing targets)
```bash
# Build Stage 0 from NASM
cd bootstrap/stage0 && make all

# Test Stage 0 on hello.jda
cd bootstrap/stage0 && make test

# Compile jda1.jda with Stage 0 (once features are added)
cd bootstrap/stage0 && make stage1

# Full self-hosting test (once features are added)
cd bootstrap/stage0 && make selfhost
```

---

## File Inventory

### New Files
```
tools/dev/
  ├── source_analyzer.py (7.5 KB)     — Feature gap analysis
  ├── source_splitter.py (10 KB)      — Source decomposition
  └── compile_workflow.sh (4.7 KB)    — Orchestration

docs/
  └── STAGE0_EXTENSION_ROADMAP.md (10 KB)  — Implementation plan
```

### Modified Files
```
Makefile                               — Added 3 targets
```

### Session Documentation
```
.copilot/session-state/.../
  ├── plan.md                         — Detailed workplan
  └── SESSION_SUMMARY.md              — Full session recap
```

---

## Environment & Dependencies

### Required
- Python 3.6+ (for analysis tools)
- Bash 4+ (for workflow script)
- NASM (for Stage 0 assembly, existing)
- Linux x86-64 (build/test target)

### Optional (for full CI)
- Docker (for Linux builds on macOS)
- GitHub Actions (for CI/CD)

### No New Dependencies
- All Python tools are stdlib only
- All shell scripts are POSIX-compatible
- No external packages or build tools added

---

## Roadmap Summary

| Week | Phase | Deliverable | Status |
|------|-------|-------------|--------|
| 1 | 1 | Python tools + roadmap | ✅ Done |
| 2 | 2.1 | Functions (fn) support | ⏳ Pending |
| 3 | 2.2+2.3 | Control flow (if/loop) | ⏳ Pending |
| 4 | 2.4+2.5 | Structs + Syscalls | ⏳ Pending |
| 5-6 | 3 | Testing & validation | ⏳ Pending |
| 7 | 4 | Docs & integration | ⏳ Pending |

**Total Timeline:** 2-3 weeks from Phase 2 start to self-hosting complete

---

## Getting Help

### For understanding the gap:
```bash
make analyze-features
```
Shows exactly what Stage 0 needs to support to compile jda1.jda.

### For understanding decomposition:
```bash
make split-source
```
Shows how large sources can be broken into manageable chunks.

### For testing workflow:
```bash
make compile-demo
```
Runs the full analysis pipeline in demo mode.

### For implementation details:
Read `docs/STAGE0_EXTENSION_ROADMAP.md` for:
- Detailed implementation approach for each feature
- Effort estimates
- Test cases
- Success criteria

---

## Contact & Progress Tracking

**Current Status:** Phase 1 complete ✅, Phase 2 pending  
**Last Updated:** February 25, 2026  

To check current progress on Phase 2+ implementation:
```bash
make analyze-features  # Shows what still needs to be done
```

When Phase 2 is complete, you'll be able to run:
```bash
make selfhost  # Stage 0 compiles jda1.jda, jda1 compiles itself
```

---

## References

- **Language Spec:** `syntax/spec.jda`
- **Stage 0 Source:** `bootstrap/stage0/jda0.asm` (2,400 lines)
- **Stage 1 Source:** `bootstrap/stage1/jda1.jda` (1,767 lines)
- **Existing Conformance:** `tests/conformance/stage0/`
- **CI Workflows:** `.github/workflows/stage0-ci.yml`

---

**This document is the master reference for the Jda self-hosting initiative. For implementation details, see the roadmap. For tooling help, run the Makefile targets.**
