# Jda

A systems programming language bootstrapped from raw x86-64 assembly. Zero dependency on C, C++, Rust, or Python at runtime. The compiler compiles itself.

## Status

**Self-hosting achieved** (April 2, 2026). The compiler reaches a fixed point:

```
jda0 (asm) → jda1 (374 KB) → jda1_sh2 (1.77 MB) → jda1_sh3 (1.77 MB) → jda1_sh4 (1.77 MB)
                                                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                                              byte-identical — converged
```

## What is Jda?

Jda is a compiled language targeting Linux x86-64, built entirely from scratch:

- **Stage 0** (`jda0`): Hand-written NASM assembler — the seed compiler
- **Stage 1** (`jda1`): The real compiler, written in Jda itself (~330K lines of `.jda`)
- **Self-host**: `jda1` compiles its own source code and produces an identical binary

No libc, no linker scripts, no runtime. Raw syscalls, raw ELF, raw machine code.

## Language Features

```jda
struct Point {
    x: i64
    y: i64
}

fn distance(a: &Point, b: &Point) -> i64 {
    let dx = b.x - a.x
    let dy = b.y - a.y
    ret dx * dx + dy * dy
}

fn main() -> i64 {
    let p1 = Point{}
    let p2 = Point{}
    p1.x = 3
    p1.y = 4
    p2.x = 6
    p2.y = 8
    let d = distance(&p1, &p2)
    print_i64(d)
    print("\n")
    ret 0
}
```

**Supported**: functions, structs, arrays, pointers, references, if/else-if/else, loops, const declarations, logical operators, inline assembly, syscalls, string literals with escapes, print/print_i64.

## Building

Requires Docker Desktop (builds target Linux x86-64 via emulation on macOS/ARM).

```bash
# Build the Docker image (once)
docker build -t jda-build docker/

# Stage 1: assemble jda0, compile jda1
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v $(PWD):/jda -w /jda/bootstrap/stage0 jda-build make stage1

# Self-host: full 4-stage pipeline
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v $(PWD)/bootstrap:/jda -w /jda/stage0 jda-build sh -c "
    ./jda1 ../stage1/jda1.jda jda1_sh2 2>/dev/null &&
    ./jda1_sh2 ../stage1/jda1.jda jda1_sh3 2>/dev/null &&
    ./jda1_sh3 ../stage1/jda1.jda jda1_sh4 2>/dev/null &&
    cmp jda1_sh3 jda1_sh4 && echo CONVERGED"
```

## Repository Layout

```
bootstrap/
  stage0/          jda0 assembler source + Makefile
  stage1/          jda1 compiler source (jda1.jda)
  selfhost/        built self-host binaries (gitignored)
docs/              project documentation
docker/            Dockerfile for build environment
examples/          example Jda programs
tests/             conformance test suite
tools/             code generators and CI scripts
```

## Documentation

- [Architecture](docs/architecture.md) — compiler internals and bootstrap pipeline
- [Roadmap](docs/roadmap.md) — project stages and future plans
