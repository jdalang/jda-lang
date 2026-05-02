# Jda

A systems programming language built from scratch — zero dependency on C, C++, Rust, or Python. Bootstrapped from raw x86-64 assembly. The compiler compiles itself.

Jda is designed to resolve the performance/safety/ergonomics trilemma:

- **Replace the C stack** — no libc, direct kernel syscalls, zero dependency conflicts
- **Displace Python in AI** — native tensor primitives and compile-time autograd, no "two-language problem"
- **Match Go's scalability** — lightweight actor-based concurrency without GC pauses
- **Emulate Ruby's joy** — clean block-based syntax, minimal boilerplate

## Current Status

**Phase 1 complete: self-hosting achieved** (April 2, 2026).

The compiler reaches a fixed point — it compiles its own source and produces an identical binary:

```
jda0 (asm) → jda1 (374 KB) → jda1_sh2 (1.77 MB) → jda1_sh3 → jda1_sh4
                                                     ^^^^^^^^^^^^^^^^^^^^^^^^
                                                     byte-identical — converged
```

C and C++ are officially eliminated from the toolchain. The Jda compiler is written entirely in Jda.

## Language Features (Current)

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

**Working**: functions, structs, arrays, pointers, references, if/else-if/else, loops, const declarations, logical operators, inline assembly, syscalls, string literals with escapes, print/print_i64, SSA-based IR with constant folding and DCE, register allocator with spill, x86-64 native code generation, ELF binary output.

## Quick Install (Linux x86-64)

```bash
curl -fsSL https://raw.githubusercontent.com/jdalang/jda-lang/main/install.sh | bash
```

Or specify a version:

```bash
JDA_VERSION=0.1.0 curl -fsSL https://raw.githubusercontent.com/jdalang/jda-lang/main/install.sh | bash
```

## Building from Source

Requires Docker Desktop (builds target Linux x86-64). No NASM or assembly tools needed — the bootstrap compiler is a self-hosted Jda binary.

```bash
# Build the Docker image (once)
docker build -t jda-build docker/

# Build jda1 from the bootstrap compiler
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v $(PWD):/jda -w /jda/bootstrap/stage0 jda-build make stage1

# Verify self-hosting convergence
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v $(PWD):/jda -w /jda/bootstrap/stage0 jda-build make selfhost
```

## CLI Usage

```bash
# Compile a .jda file (output name derived from input: hello.jda → hello)
jda build hello.jda

# Compile with explicit output path
jda build hello.jda -o my_binary

# Compile and run immediately
jda run hello.jda

# Show version
jda --version

# Show help
jda --help
```

Legacy syntax is also supported for backward compatibility:

```bash
jda hello.jda output_binary
```

### Standard Library

Use `--include` to link the standard library prelude (fs, fmt, time):

```bash
jda build --include stdlib/prelude.jda myapp.jda
jda run --include stdlib/prelude.jda myapp.jda
```

Available functions:

| Module | Functions |
|--------|-----------|
| **fmt** | `fmt_i64(buf, val)`, `fmt_hex(buf, val)`, `str_len(s)`, `str_eq(a,b)`, `str_copy`, `mem_set`, `print_str`, `print_int` |
| **fs** | `fs_read_file(path, buf, max)`, `fs_write_file(path, data, len)`, `fs_append_file`, `fs_exists`, `fs_unlink`, `fs_mkdir`, `fs_file_size` |
| **time** | `time_now_ns()`, `time_now_ms()`, `time_sleep_ms(ms)`, `time_elapsed_ns(start)`, `time_unix_secs()` |

See `stdlib/prelude.jda` for full API. Individual modules also available: `stdlib/fs.jda`, `stdlib/fmt.jda`, `stdlib/time.jda`.

## Repository Layout

```
bootstrap/
  bin/             jda1-bootstrap binary (self-hosted, checked in)
  stage0/          jda0 assembler source (legacy) + Makefile
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
- [Roadmap](docs/roadmap.md) — from self-hosting through ML runtime and ecosystem
- [Vision](docs/vision.md) — design philosophy and the convergence architecture

## Design Documents

The original design specification is in the `.docx` files at the project root:
- `Jda_A_Convergence_Architecture_for_Post-Moore_Systems_Programming.docx`
- `Jda-Language-Technical-Implementation-Guide.docx`
- `Jda-AI-Prompt-Master-Guide.docx`
