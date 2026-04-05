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
- **33x faster compilation than Rust** — 42ms average compile time ([benchmarks](benchmarks/RESULTS.md))
- **Beats C on 2 of 4 benchmarks** — faster than gcc -O2 on sieve and sum loop
- **24–53x faster than Python/Ruby** — compiled performance with scripting-speed iteration
- **114 stdlib packages** — data structures, networking, crypto, JSON, HTTP, ML/AI, and more
- **361 conformance tests** — all passing
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

## Real-World Examples

**jda-grep** — ripgrep-style text search (~400 lines, 1 MB static binary)

```jda
fn search_file(path: &i8, pattern: &i8, pat_len: i64) -> i64 {
    let fd = file_open(path, 0)
    let buf = file_read_all(fd)
    let matches = 0
    let line_num = 1
    for i in range(str_len(buf)) {
        if substr_match(buf, i, pattern, pat_len) {
            print_match(path, line_num, buf, i)
            matches += 1
        }
        if byte_at(buf, i) == 10 { line_num += 1 }
    }
    file_close(fd)
    ret matches
}
```

**Log analyzer** — process GB-scale server logs natively

```jda
fn analyze_log(path: &i8) -> i64 {
    let fd = file_open(path, 0)
    let total = 0
    let errors = 0
    let latency_sum: f64 = 0.0
    loop file_eof(fd) == 0 {
        let line = file_read_line(fd)
        total += 1
        if str_contains(line, "ERROR") { errors += 1 }
        let ms = parse_latency(line)
        latency_sum = latency_sum + ms
    }
    let avg = latency_sum / int_to_f64(total)
    print("Lines: {total}  Errors: {errors}\n")
    print_f64("Avg latency: ", avg, " ms\n")
    ret 0
}
```

**File search indexer** — build an in-memory index over a directory tree

```jda
fn index_directory(root: &i8) -> &HashMap {
    let index = hashmap_new()
    let files = find(root, "*.jda")
    for i in range(vec_len(files)) {
        let path = vec_get_str(files, i)
        let content = file_read_all_str(path)
        let words = str_split(content, " ")
        for j in range(vec_len(words)) {
            let w = vec_get_str(words, j)
            hashmap_set(index, w, path)
        }
    }
    ret index
}
```

All three compile to **< 1.1 MB static ELF binaries** with zero external dependencies.

**[→ Getting Started Guides](docs/getting-started/)** — build a CLI tool, an HTTP server, or train a neural network step by step.

## Language Features

**Core**: functions, structs, arrays, pointers, references, if/else, loops, const, enums, generics, closures, pattern matching, inline assembly

**Type System**: i64, i32, i8, f64, &T references, const generics (`fn foo<const N>()`), traits, derive macros (Debug, Eq, Clone, Hash, Ord)

**OOP**: struct + trait + impl (Rust-style), method dispatch, operator overloading

**Concurrency**: spawn/channels, green threads, deadlock detection, atomic ops

**Compiler**: SSA IR, constant folding, DCE, tail call optimization, loop register promotion, peephole opts, register allocator with spill, x86-64 native codegen, ELF output

## Download & Install

| Platform | Download | Install |
|----------|----------|---------|
| **Windows** | [`.exe` installer](https://github.com/jdalang/jda-lang/releases/latest) | Double-click |
| **macOS** | [`.pkg` installer](https://github.com/jdalang/jda-lang/releases/latest) | Double-click |
| **Ubuntu/Debian** | [`.deb` package](https://github.com/jdalang/jda-lang/releases/latest) | `sudo dpkg -i jda_*.deb` |
| **Fedora/RHEL** | [`.rpm` package](https://github.com/jdalang/jda-lang/releases/latest) | `sudo rpm -i jda-*.rpm` |
| **Any Linux/macOS** | Shell script | `curl -fsSL https://raw.githubusercontent.com/jdalang/jda-lang/main/install.sh \| sh` |

**Multiple versions?** Use the [Jda Version Manager](docs/getting-started/installation.md#version-manager):

```bash
curl -fsSL https://raw.githubusercontent.com/jdalang/jda-lang/main/install-jdavm.sh | sh
jdavm install latest
jdavm install 0.1.1
jdavm use 0.2.0
```

**[→ Full installation guide](docs/getting-started/installation.md)** — all platforms, options, troubleshooting, uninstall

## Building from Source

Requires Docker (any OS). No NASM or assembly tools needed — the bootstrap compiler is a self-hosted Jda binary.

```bash
git clone https://github.com/jdalang/jda-lang.git && cd jda-lang

# Build the Docker image (once)
docker build --platform linux/amd64 -t jda-build docker/

# Build the compiler
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v $(PWD):/jda -w /jda/bootstrap/stage0 jda-build make stage1

# Run the test suite (361 tests)
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

> Best of 3 runs, Docker (Ubuntu 22.04 linux/amd64) on macOS Apple Silicon. All languages tested in the same environment. [Full analysis](benchmarks/RESULTS.md) | [Source code](benchmarks/)

### Runtime (ms)

| Benchmark | C | Jda | Rust | Go | Python | Ruby |
|-----------|----:|--------:|------:|-----:|-------:|-----:|
| sieve 1M | 27 | **24** | 31 | 32 | 416 | 408 |
| matmul 200x200 | 30 | 37 | 32 | 40 | 2,265 | 998 |
| sum 100M | 57 | **49** | 30 | 80 | 8,183 | 3,615 |
| fib(35) | 40 | 148 | 62 | 126 | 2,826 | 1,318 |
| json parse 50K | 32 | **31** | 33 | 90 | 159 | 342 |

### Compile Time (ms)

| Benchmark | C (gcc -O2) | Jda | Rust (rustc -O) | Go |
|-----------|--------:|--------:|------:|----:|
| sieve 1M | 479 | **45** | 1,579 | 658 |
| matmul 200x200 | 478 | **42** | 1,628 | 695 |
| sum 100M | 434 | **40** | 1,209 | 678 |
| fib(35) | 495 | **42** | 1,269 | 746 |
| json parse 50K | 510 | **48** | 1,726 | 789 |

### Binary Size

| | C | Jda | Rust | Go |
|---|------:|--------:|---------:|----------:|
| Size | 16 KB | 1.05 MB | 3.95 MB | 1.76 MB |
| Linking | dynamic | static | static | static |

### Head-to-Head

| | vs C | vs Rust | vs Go | vs Python | vs Ruby |
|---|---|---|---|---|---|
| **Runtime** | **Jda wins 3 of 5** | **Jda wins 2 of 5** | **Jda wins 4 of 5** | **Jda 54x faster** | **Jda 28x faster** |
| **Compile** | **Jda 11x faster** | **Jda 33x faster** | **Jda 16x faster** | — | — |
| **Binary** | C 65x smaller (dynamic) | **Jda 3.8x smaller** | **Jda 40% smaller** | — | — |
| **GC** | Neither | Neither | **Jda: no GC** | — | — |
| **Deps** | gcc + libc | Rust toolchain | Go toolchain | CPython | CRuby |

Jda: **zero external dependencies** — bootstrapped from assembly, single static binary.

<details>
<summary>Reproduce</summary>

```bash
docker build --platform linux/amd64 -t jda-bench benchmarks/
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v $(pwd):/jda -w /jda jda-bench bash /jda/benchmarks/run.sh
```

</details>

## Tooling

### VS Code Extension

Syntax highlighting, LSP integration, and snippets for `.jda` files.

```bash
# Install from source
cd tools/vscode-jda && code --install-extension .
```

Features: syntax highlighting, bracket matching, auto-indent, comment toggling, LSP hover/diagnostics/completion, and code snippets (`fn`, `struct`, `impl`, `for`, `match`).

See [tools/vscode-jda/](tools/vscode-jda/) for details.

### Version Manager (jdavm)

Install and switch between multiple Jda versions — like rustup, nvm, or rvm.

```bash
# Install jdavm
curl -fsSL https://raw.githubusercontent.com/jdalang/jda-lang/main/install-jdavm.sh | sh

# Install and switch versions
jdavm install latest         # download latest release
jdavm install 0.1.1          # install older version
jdavm use 0.2.0              # switch active version
jdavm list                   # see installed versions
```

Works on **Linux** and **macOS** natively. On **Windows**, use inside WSL2.

### CLI Tools

| Tool | Command | Description |
|------|---------|-------------|
| Compiler | `jda build` / `jda run` | Compile and run `.jda` files |
| Formatter | `jda fmt` | Format source code |
| Test runner | `jda test` | Run test files with assertions |
| Benchmarker | `jda bench` | Benchmark `fn bench_*` functions |
| Doc generator | `jda doc` | Generate HTML/Markdown docs from comments |
| Package manager | `jda pkg` | Install, search, and manage stdlib packages |
| Fuzzer | `jda fuzz` | Fuzz test `fn fuzz_*` functions |
| Race detector | `jda race` | Detect data races on globals |
| LSP server | `jda-lsp` | Language Server Protocol for editors |

## Repository Layout

```
apps/              Real applications (jda-grep)
bootstrap/
  stage0/          Build system + jda0 (assembly bootstrap)
  stage1/          jda1 compiler source (jda1.jda — self-hosted)
stdlib/            114 standard library packages
tools/             CLI tools (jda, jdavm, jda-doc, jda-test, jda-pkg, etc.)
tests/             361 conformance tests (pass + fail)
benchmarks/        Performance benchmarks (Jda vs C/Go/Rust/Python/Ruby)
examples/          Example programs
installers/        Native installers (.deb, .rpm, .pkg, .exe)
docs/
  getting-started/ Hands-on guides (CLI tool, HTTP server, ML)
  language/        Language reference (syntax, structs/OOP, stdlib, toolchain, compiler)
  stdlib/          HTML API docs (generated by jda-doc)
  stdlib-md/       Markdown API docs for GitHub (generated by jda-doc-md)
  contributing/    Contributing guide
prompts/           LLM system prompts for AI coding assistants
docker/            Dockerfile for build environment
```

## Documentation

### Getting Started
- [Build a CLI Tool](docs/getting-started/cli-tool.md) — word-count tool with args, file I/O
- [Build an HTTP Server](docs/getting-started/http-server.md) — static file server with raw syscalls
- [Train a Neural Network](docs/getting-started/ml-example.md) — XOR MLP from scratch with f64

### Language Reference (Markdown — GitHub)
- [Syntax](docs/language/syntax.md) — variables, types, functions, control flow, operators
- [Structs & OOP](docs/language/structs.md) — structs, traits, impl, derive, generics, closures, unsafe
- [Standard Library](docs/language/stdlib.md) — all 114 packages by category
- [Toolchain](docs/language/toolchain.md) — CLI commands, package manager, doc generator, testing
- [Compiler Architecture](docs/language/compiler.md) — pipeline, data structures, self-hosting

### API Reference
- [Markdown docs](docs/stdlib-md/index.md) — GitHub-compatible, per-package API reference
- [HTML docs](docs/stdlib/) — website-ready, generated by `jda doc`

### LLM / AI Integration
- [LLM Context File](docs/llm-context.md) — complete language reference in one file, optimized for LLM context windows
- [System Prompt](prompts/jda-assistant.md) — ready-to-use system prompt for ChatGPT, Claude, etc.
- [llms.txt](llms.txt) — standardized LLM discovery file

Feed `docs/llm-context.md` into any LLM to enable it to write correct Jda code.

### Contributing
- [Contributing Guide](CONTRIBUTING.md) — how to build, test, and submit changes
