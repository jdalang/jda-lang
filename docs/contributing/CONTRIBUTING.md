# Contributing to Jda

Thank you for your interest in contributing to Jda! This document explains how to get started.

## Getting Started

1. **Fork** the repository on GitHub
2. **Clone** your fork locally
3. **Build** the Docker image: `docker build -t jda-build docker/`
4. **Build** the compiler: see [Building from Source](../language/toolchain.md#building-from-source)

## Development Workflow

### Making Changes

1. Create a feature branch: `git checkout -b my-feature`
2. Make your changes
3. Run the conformance tests:
   ```bash
   docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
     -v $(PWD):/jda -w /jda jda-build bash tools/run_tests.sh
   ```
4. Verify self-hosting (if compiler changes):
   ```bash
   docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
     -v $(PWD)/bootstrap:/jda -w /jda/stage0 jda-build sh -c \
     "./jda1 ../stage1/jda1.jda jda1_sh2 2>/dev/null; echo EXIT:\$?"
   ```
5. Commit and push
6. Open a pull request

### What to Contribute

- **Stdlib packages**: New packages in `stdlib/` are always welcome
- **Conformance tests**: Test cases in `tests/conformance/stage1/pass/`
- **Example programs**: Practical examples in `examples/`
- **Documentation**: Docs in `docs/` (markdown for GitHub, HTML via `jda doc`)
- **Bug fixes**: Fix issues in the compiler (`bootstrap/stage1/jda1.jda`)
- **Tools**: Improvements to `tools/` scripts

### Coding Standards

- Use `;;` doc comments for public functions
- Follow naming convention: `module_function_name()` (e.g., `vec_push`, `sort_reverse`)
- Include a header comment block in new stdlib files:
  ```jda
  ; =============================================================================
  ; jda::mypackage -- Short Description
  ; =============================================================================
  ; Longer description of what this package does.
  ;
  ; Functions:
  ;   mypackage_foo(x)       -> i64   description
  ;   mypackage_bar(a, b)             description
  ; =============================================================================
  ```
- Memory layout documentation for data structures
- Every new stdlib package should be added to `stdlib/PACKAGES.md`

### Writing Tests

Add conformance tests as pairs:

```
tests/conformance/stage1/pass/my_feature.jda       # test program
tests/conformance/stage1/pass/my_feature.expected   # expected stdout
```

For tests that should fail to compile:

```
tests/conformance/stage1/fail/bad_syntax.jda        # should not compile
tests/conformance/stage1/fail/bad_syntax.expected    # expected error substring
```

### Pull Request Guidelines

- Keep PRs focused on a single feature or fix
- Include conformance tests for new features
- Update `stdlib/PACKAGES.md` for new stdlib packages
- Run the full test suite before submitting
- Describe what changed and why in the PR description

## Architecture Overview

```
bootstrap/
  stage0/          Build system and jda0 (assembly bootstrap)
  stage1/          jda1 compiler source (jda1.jda — the compiler)
stdlib/            Standard library packages (.jda files)
tools/             CLI tools (jda, jda-doc, jda-test, etc.)
tests/             Conformance test suite
examples/          Example programs
docs/              Documentation (markdown + HTML)
```

The compiler pipeline: **source → tokens → AST → JIR (SSA) → x86-64 → ELF binary**

## Known Workarounds

Due to jda0 bootstrap limitations, the following workarounds exist in jda1.jda:

- No unconditional `loop {}` — use `loop var == 1 {}`
- No `out[idx] = val` for byte stores — use `poke_byte(out, idx, val)`
- `a - b - c` parses right-associatively — use temp variables
- Closures must capture at least one variable
- Max 1 syscall per function — use single-syscall wrappers

These only affect the compiler itself. User programs compiled by jda1 do not have these limitations.

## Questions?

Open an issue at [github.com/jdalang/jda-lang/issues](https://github.com/jdalang/jda-lang/issues).
