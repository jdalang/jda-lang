<p align="center">
  <img src="assets/jda-logo.png" alt="Jda Programming Language" width="300">
</p>

<h1 align="center">Jda</h1>

<p align="center"><strong>A high-performance systems language with built-in concurrency and ML — without GC.</strong><br>Bootstrapped from raw x86-64 assembly. The compiler compiles itself.</p>

<p align="center">
  <a href="#installation">Install</a> &bull;
  <a href="docs/language/syntax.md">Docs</a> &bull;
  <a href="docs/language/stdlib.md">Stdlib</a> &bull;
  <a href="benchmarks/RESULTS.md">Benchmarks</a> &bull;
  <a href="examples/">Examples</a> &bull;
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

---

## Highlights

- **Self-hosted** — the compiler is written entirely in Jda (zero C/C++/Rust)
- **Bootstrapped from assembly** — no external compiler dependency
- **32x faster compilation than Rust** — 44ms average compile time ([benchmarks](benchmarks/RESULTS.md))
- **Beats C on sieve benchmark** — competitive native code from a self-hosted compiler
- **12–24x faster than Python/Ruby** — compiled performance with scripting-speed iteration
- **114 stdlib packages** — data structures, networking, crypto, JSON, HTTP, ML/AI, and more
- **350 conformance tests** — all passing
- **Cross-platform** — native on Linux, Docker-based on macOS/Windows
- **Built-in concurrency** — goroutine-style green threads with channels
- **ML primitives** — tensors, autograd, neural networks, AVX-512 acceleration

## Current Status

**Self-hosting converged** (April 2, 2026). The compiler compiles itself and produces a byte-identical binary:

```
jda0 (asm) → jda1 (374 KB) → jda1_sh2 (2.1 MB) → jda1_sh3
                                                    ^^^^^^^^
                                                    identical — fixed point
```

## Quick Example

```jda
struct Point { x: i64  y: i64 }

fn distance(a: &Point, b: &Point) -> i64 {
    let dx = b.x - a.x
    let dy = b.y - a.y
    ret dx * dx + dy * dy
}

fn main() -> i64 {
    let p1 = Point{}
    let p2 = Point{}
    p1.x = 3   p1.y = 4
    p2.x = 6   p2.y = 8
    let d = distance(&p1, &p2)
    print("{d}\n")
    ret 0
}
```

```bash
$ jda run example.jda
25
```

## Language Features

**Core**: functions, structs, arrays, pointers, references, if/else, loops, const, enums, generics, closures, pattern matching, inline assembly

**Type System**: i64, i32, i8, f64, &T references, const generics (`fn foo<const N>()`), traits, derive macros (Debug, Eq, Clone, Hash, Ord)

**OOP**: struct + trait + impl (Rust-style), method dispatch, operator overloading

**Concurrency**: spawn/channels, green threads, deadlock detection, atomic ops

**Compiler**: SSA IR, constant folding, DCE, tail call optimization, peephole opts, register allocator with spill, x86-64 native codegen, ELF output

## Installation

### Linux / macOS / WSL2 / FreeBSD

```bash
curl -fsSL https://raw.githubusercontent.com/jdalang/jda-lang/main/install.sh | sh
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/jdalang/jda-lang/main/install.ps1 | iex
```

### Windows (CMD)

```cmd
curl -o install.bat https://raw.githubusercontent.com/jdalang/jda-lang/main/install.bat && install.bat
```

The installer auto-detects your platform and chooses the best method:

| Platform | Method | Requirements |
|----------|--------|-------------|
| Linux x86-64 | **Native binary** | None |
| Linux ARM64 | Docker emulation | Docker |
| macOS (Intel / Apple Silicon) | Docker | [Docker Desktop](https://docs.docker.com/desktop/install/mac-install/) |
| Windows 10/11 | WSL2 *(recommended)* | `wsl --install` then run the Linux installer inside WSL |
| Windows 10/11 | Docker | [Docker Desktop](https://docs.docker.com/desktop/install/windows-install/) |
| FreeBSD x86-64 | Native (Linux compat) | `sysctl kern.elf64.fallback_brand=3` |
| ChromeOS | Linux (Crostini) | Enable Linux dev environment |

<details>
<summary>Installer options</summary>

```bash
# Install a specific version
JDA_VERSION=0.1.0 curl -fsSL .../install.sh | sh

# Custom install directory
JDA_INSTALL_DIR=/opt/jda curl -fsSL .../install.sh | sh

# Skip PATH modification
JDA_NO_MODIFY_PATH=1 curl -fsSL .../install.sh | sh

# Uninstall
curl -fsSL .../install.sh | sh -s -- --uninstall

# Windows uninstall
.\install.ps1 -Uninstall
```

</details>

See [docs/INSTALL.md](docs/INSTALL.md) for the full installation guide, troubleshooting, and building from source.

## Building from Source

Requires Docker (any OS). No NASM or assembly tools needed — the bootstrap compiler is a self-hosted Jda binary.

```bash
git clone https://github.com/jdalang/jda-lang.git && cd jda-lang

# Build the Docker image (once)
docker build --platform linux/amd64 -t jda-build docker/

# Build the compiler
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v $(PWD):/jda -w /jda/bootstrap/stage0 jda-build make stage1

# Run the test suite (350 tests)
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v $(PWD):/jda -w /jda jda-build bash tools/run_tests.sh

# Verify self-hosting (compiler compiles itself)
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

### Standard Library (114 packages)

Use `--include` to link standard library packages:

```bash
jda build --include stdlib/prelude.jda myapp.jda
jda build --include stdlib/vec.jda --include stdlib/sort.jda myapp.jda
```

Or install packages locally:

```bash
jda pkg install vec           # copy to lib/
jda pkg install sort
jda pkg search hash           # search packages
```

**Data Structures**: vec, hashmap, set, queue, heap, ring, matrix, tuple, kvstore
**Algorithms**: sort, iter, comprehension, tsort, diff, statistics
**Strings/Encoding**: string, fmt, conv, regex, base64, json, csv, uri, textwrap, toml, configparser, xml, htmlparser, email
**I/O & Filesystem**: fs, file_io, find, tempfile, glob, mmap, gzip, tarfile, zipfile, linecache, copy
**Networking**: net/tcp, net/http, net/ws, ipaddr, dns, socketserver, httpserver, httpclient, smtp, ftp, netrc
**System**: os, process, time, timeout, context, args, shell, platform, errno, getpass, sched, signal, mmap
**Crypto**: crypto (AES, SHA-256, ChaCha20), uuid, securerandom, digest
**Math**: math, bitops, fixedpoint, bignum, complex, rational, datetime, calendar
**Testing**: testing, benchmark, log, pp
**AI/ML**: tensor_ops, autograd, nn, transformer, avx512_ops, ptx, rocm
**Patterns**: decorator, dataclass, observer, enum, operator, marshal, pack, encoding, erb, fnmatch, mimetypes, compress

See [stdlib/PACKAGES.md](stdlib/PACKAGES.md) for the complete list, or [docs/stdlib-md/](docs/stdlib-md/index.md) for full API docs.

### OOP Model

Jda uses **struct + trait + impl** (like Rust, not class-based):

```jda
trait Shape {
    fn area(self: &Self) -> i64
}

struct Circle { radius: i64 }

impl Shape for Circle {
    fn area(self: &Circle) -> i64 { ret self.radius * self.radius * 3 }
}

derive(Debug, Eq, Clone)
struct Config { width: i64  height: i64 }
```

See [docs/language/structs.md](docs/language/structs.md) for the full OOP guide.

## Benchmarks

> Best of 3 runs, Linux x86-64 (Docker, Ubuntu 22.04). [Full analysis](benchmarks/RESULTS.md) | [Source code](benchmarks/)

### Runtime (ms)

| Benchmark | C | Go | Rust | Jda | Python | Ruby |
|-----------|----:|-----:|------:|--------:|-------:|-----:|
| fib(35) | 41 | 127 | 63 | 156 | 2,829 | 1,288 |
| sieve 1M | 27 | 32 | 31 | **23** | 442 | 388 |
| sum 100M | 26 | 79 | 29 | 283 | 8,005 | 3,594 |
| matmul 200x200 | 29 | 40 | 31 | 47 | 2,295 | 988 |

### Compile Time (ms)

| Benchmark | C (gcc -O2) | Go | Rust (rustc -O) | Jda |
|-----------|--------:|----:|------:|--------:|
| fib(35) | 555 | 804 | 1,339 | **45** |
| sieve 1M | 474 | 683 | 1,580 | **47** |
| sum 100M | 390 | 669 | 1,207 | **40** |
| matmul 200x200 | 464 | 667 | 1,596 | **43** |

### Binary Size

| | C | Go | Rust | Jda |
|---|------:|----------:|---------:|--------:|
| Size | 16 KB | 1.76 MB | 3.95 MB | 1.05 MB |
| Linking | dynamic | static | static | static |

### Head-to-Head

| | vs C | vs Go | vs Rust | vs Python | vs Ruby |
|---|---|---|---|---|---|
| **Runtime** | Jda 0.85x–10.9x of C | Mixed | Rust ~1.3x faster | **Jda 24x faster** | **Jda 12x faster** |
| **Compile** | **Jda 10.7x faster** | **Jda 16x faster** | **Jda 32.5x faster** | — | — |
| **Binary** | C 65x smaller (dynamic) | **Jda 40% smaller** | **Jda 3.8x smaller** | — | — |
| **GC** | Neither | **Jda: no GC** | Neither | — | — |
| **Deps** | gcc + libc | Go toolchain | Rust toolchain | CPython | CRuby |

Jda: **zero external dependencies** — bootstrapped from assembly, single static binary.

<details>
<summary>Reproduce</summary>

```bash
docker build --platform linux/amd64 -t jda-bench benchmarks/
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v $(pwd):/jda -w /jda jda-bench bash /jda/benchmarks/run.sh
```

</details>

## Repository Layout

```
bootstrap/
  stage0/          Build system + jda0 (assembly bootstrap)
  stage1/          jda1 compiler source (jda1.jda — self-hosted)
stdlib/            114 standard library packages
tools/             CLI tools (jda, jda-doc, jda-test, jda-pkg, etc.)
tests/             350 conformance tests (pass + fail)
benchmarks/        Performance benchmarks (Jda vs C/Go/Rust/Python/Ruby)
examples/          Example programs
docs/
  language/        Language reference (syntax, structs/OOP, stdlib, toolchain, compiler)
  stdlib/          HTML API docs (generated by jda-doc)
  stdlib-md/       Markdown API docs for GitHub (generated by jda-doc-md)
  contributing/    Contributing guide
docker/            Dockerfile for build environment
```

## Documentation

### Language Reference (Markdown — GitHub)
- [Syntax](docs/language/syntax.md) — variables, types, functions, control flow, operators
- [Structs & OOP](docs/language/structs.md) — structs, traits, impl, derive, generics, closures, unsafe
- [Standard Library](docs/language/stdlib.md) — all 114 packages by category
- [Toolchain](docs/language/toolchain.md) — CLI commands, package manager, doc generator, testing
- [Compiler Architecture](docs/language/compiler.md) — pipeline, data structures, self-hosting

### API Reference
- [Markdown docs](docs/stdlib-md/index.md) — GitHub-compatible, per-package API reference
- [HTML docs](docs/stdlib/) — website-ready, generated by `jda doc`

### Contributing
- [Contributing Guide](CONTRIBUTING.md) — how to build, test, and submit changes

### Design Documents
- `Jda_A_Convergence_Architecture_for_Post-Moore_Systems_Programming.docx`
- `Jda-Language-Technical-Implementation-Guide.docx`
- `Jda-AI-Prompt-Master-Guide.docx`
