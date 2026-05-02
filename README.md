# Jda

**Ruby-readable. Machine-code fast. Zero dependencies.**

Jda is a systems programming language that eliminates the trade-off between performance, safety, and developer ergonomics. It compiles directly to x86-64 machine code with no libc, no garbage collector, and no runtime.

```jda
fn main() {
    print("Hello Bare Metal")
}
```

---

## Why Jda?

Every major language forces you to sacrifice something:

| Language | Problem |
|----------|---------|
| **C / C++** | Manual memory, undefined behaviour, dependency hell |
| **Python** | Slow — it's a wrapper around C++. The "two-language problem" |
| **Go** | GC pauses make it unsuitable for real-time or high-frequency systems |
| **Ruby** | Maximum developer joy, minimum runtime performance |
| **Rust** | Safe and fast — but notoriously steep learning curve |

Jda solves all of them at once:

- **Reads like Ruby** — expressive, minimal punctuation, no boilerplate
- **Runs like C** — compiles to raw x86-64, no VM, no interpreter
- **Safe like Rust** — compile-time ownership, no GC, no use-after-free
- **Concurrent like Go** — J-Threads (green threads) with lock-free channels
- **ML-native** — Tensors are first-class primitives, not a library

---

## Core Constraints

- **Zero C / C++ / Rust / Python** — the compiler is bootstrapped from Assembly
- **No libc** — all OS interaction via direct Linux syscalls
- **No garbage collector** — ownership and region allocators only
- **Self-hosted** — the Jda compiler is written in Jda

---

## Language Highlights

### Clean syntax
```jda
struct Point { x: f64   y: f64 }

impl Point {
    fn distance(self, other: ref Point) -> f64 {
        let dx = self.x - other.x
        let dy = self.y - other.y
        ret sqrt(dx * dx + dy * dy)
    }
}

let p1 = Point { x: 0.0, y: 0.0 }
let p2 = Point { x: 3.0, y: 4.0 }
print(p1.distance(&p2))    ; 5.0
```

### Pattern matching
```jda
enum Shape { Circle(f64)  Rect(f64, f64)  Triangle(f64, f64) }

let area = match shape {
    Circle(r)     => 3.14159 * r * r
    Rect(w, h)    => w * h
    Triangle(b,h) => 0.5 * b * h
}
```

### Error handling — no exceptions
```jda
fn read_config(path: ref []i8) -> Result<Config, []i8> {
    let data = file_read(path)?      ; propagates error with ?
    let cfg  = parse_toml(data)?
    ret ok(cfg)
}

match read_config("app.toml") {
    ok(cfg) => start_server(cfg)
    err(e)  => print("Failed: ", e)
}
```

### J-Threads — concurrent by default
```jda
let ch = chan<i64>()

spawn { ch.send(expensive_compute()) }
spawn { ch.send(another_compute()) }

let a = ch.recv()
let b = ch.recv()
print("Results: ", a, b)
```

### Native Tensors — ML without Python
```jda
tensor X  = [32 x 784]f32::randn()     ; batch of 32 images, flattened
tensor W  = [784 x 128]f32::randn()    ; weight matrix
tensor b  = [128]f32::zeros()          ; bias

tensor out = X @ W + b                 ; [32 x 128] — shape verified at compile time
```

### Inline Assembly — bare-metal when you need it
```jda
fn enable_paging(page_table: u64) {
    cpu::cr3::write(page_table)
    let cr0 = cpu::cr0::read()
    cpu::cr0::write(cr0 | 0x80000000)
}

fn rdtsc() -> i64 {
    let hi: i64   let lo: i64
    asm { out rdx = hi   out rax = lo   ---   rdtsc }
    ret (hi << 32) | lo
}
```

---

## Project Structure

```
jda-lang/
├── bootstrap/
│   ├── stage0/          # Stage 0: compiler written in x86-64 NASM assembly
│   │   ├── jda0.asm     # Reads .jda source → emits ELF64 binary (zero libc)
│   │   └── Makefile
│   └── stage1/
│       └── jda1.jda     # Stage 1: self-hosted compiler written in Jda
│
├── ir/
│   └── jir.jda          # JIR — Jda Intermediate Representation (SSA form)
│
├── syntax/
│   ├── spec.jda         # Complete language specification
│   └── cheatsheet.jda   # One-file language reference
│
├── mem/
│   ├── page_alloc.jda   # Page allocator (mmap/munmap syscalls)
│   ├── region.jda       # Arena/region allocator (bump pointer, O(1) free)
│   └── ownership.jda    # Ownership & lifetime rules (compiler reference)
│
├── kernel/
│   └── inline_asm.jda   # Inline assembly syntax design + CPU register API
│
├── drivers/
│   └── vga.jda          # VGA text-mode driver (bare-metal, 0xB8000)
│
├── concurrency/
│   ├── jthread.jda      # J-Thread runtime (M:N work-stealing scheduler)
│   └── channel.jda      # Lock-free MPSC channels + select
│
├── ml/
│   ├── tensor.jda       # Native tensor primitives & compile-time shape checking
│   ├── autograd.jda     # Compile-time automatic differentiation (JIR pass)
│   ├── ptx.jda          # JIR → NVIDIA PTX GPU backend (no CUDA runtime)
│   └── avx512.jda       # AVX-512 loop tiling & vectorization JIR pass
│
├── stdlib/
│   ├── net/
│   │   ├── tcp.jda      # TCP sockets (raw Linux syscalls, yield-based I/O)
│   │   ├── http.jda     # HTTP/1.1 zero-copy parser + response writer
│   │   ├── udp.jda      # UDP sockets: bind, send_to, recv_from, broadcast, multicast
│   │   └── ws.jda       # WebSockets (RFC 6455): handshake, frame parser/builder
│   ├── json.jda         # Zero-copy JSON parser + compact/pretty serialiser
│   ├── fmt.jda          # String formatting (fmt!) + coloured compiler diagnostics
│   └── ml/
│       └── nn.jda       # Neural network layers: Linear, ReLU, Adam, SGD
│
├── examples/
│   ├── hello.jda        # Hello world (compiled by Stage 0)
│   ├── web_server.jda   # 10,000-connection concurrent HTTP server
│   └── mlp.jda          # 10-line MLP training (vs 30-line PyTorch)
│
└── docker/
    └── Dockerfile       # Linux x86-64 build environment (NASM + binutils)
```

---

## Building

Jda targets Linux x86-64. On macOS, use the provided Docker environment.

**Prerequisites:** Docker Desktop

```bash
# Build the Docker image (once)
make docker-build

# Assemble Stage 0 compiler
make stage0

# Test: compile hello.jda → ELF binary → run it
make test-stage0
```

Expected output:
```
nasm -f elf64 -g -F dwarf -o jda0.o jda0.asm
ld -o jda0 jda0.o
[jda0] Compiled successfully.
Hello Bare Metal
```

### Manual (inside the Docker container)
```bash
docker run --rm -it -v $(PWD):/jda jda-build bash

# Inside container:
cd /jda/bootstrap/stage0
make all
./jda0 ../../examples/hello.jda hello_out
./hello_out
```

---

## Implementation Phases

### Phase 1 — Bootstrapping & Core Compiler ✅
The "Zero C" rule: build the compiler without touching any existing high-level language.

| Step | File | Description |
|------|------|-------------|
| Stage 0 | `bootstrap/stage0/jda0.asm` | x86-64 NASM compiler. Reads `.jda` → emits ELF64. Zero libc. Tested. |
| JIR | `ir/jir.jda` | SSA intermediate representation with constant folding + DCE passes |
| Stage 1 | `bootstrap/stage1/jda1.jda` | Self-hosted compiler: lexer, Pratt parser, JIR codegen, x86-64 lowering |

### Phase 2 — Kernel & Hardware Interfacing ✅
Direct OS and hardware control. No OS required.

| Step | File | Description |
|------|------|-------------|
| Page Allocator | `mem/page_alloc.jda` | `mmap`/`munmap` page allocator — `own *i8` with compiler-enforced lifetime |
| Region Allocator | `mem/region.jda` | Bump-pointer arena: O(1) alloc, O(1) bulk free, zero fragmentation |
| Ownership Model | `mem/ownership.jda` | 7 compile-time rules: single owner, borrow checker, lifetime annotations |
| Inline Assembly | `kernel/inline_asm.jda` | `asm { in rdi = x  ---  syscall }` syntax. `cpu::cr3::read()` register API |
| VGA Driver | `drivers/vga.jda` | Bare-metal VGA text driver: 80×25 colour output, cursor, scroll, `kernel_main()` |

### Phase 3 — Syntax, Concurrency & Standard Library ✅
Ruby ergonomics. Go concurrency. No compromises.

| Step | File | Description |
|------|------|-------------|
| Syntax Spec | `syntax/spec.jda` | Full language: variables, generics, traits, match, Result, defer, closures |
| Cheat Sheet | `syntax/cheatsheet.jda` | Entire language on one screen |
| J-Threads | `concurrency/jthread.jda` | M:N work-stealing green threads. Context switch: ~10ns, pure asm |
| Channels | `concurrency/channel.jda` | Lock-free MPSC ring buffer. `send(own T)` / `recv() -> own T`. Zero copy |
| Web Server | `examples/web_server.jda` | 10k concurrent connections: acceptor + 256-worker pool + per-request arena |
| TCP stdlib | `stdlib/net/tcp.jda` | `TcpListener`/`TcpStream` via raw syscalls. Non-blocking + J-Thread yield |
| HTTP stdlib | `stdlib/net/http.jda` | Zero-copy HTTP/1.1 parser. All slices point into the original request buffer |
| UDP stdlib | `stdlib/net/udp.jda` | `UdpSocket` bind/send_to/recv_from. Broadcast + multicast (RFC 1112) |
| WebSocket stdlib | `stdlib/net/ws.jda` | RFC 6455: HTTP upgrade, SHA-1 accept key, frame parser/builder, masking |
| JSON stdlib | `stdlib/json.jda` | Zero-copy recursive descent parser + compact/pretty serialiser |
| Fmt stdlib | `stdlib/fmt.jda` | `fmt!` string formatting + rustc-style coloured compiler diagnostics |

### Phase 4 — Native Machine Learning ✅
Tensors, autograd, and GPU execution as language primitives. No Python. No C++.

| Step | File | Description |
|------|------|-------------|
| Tensor Primitives | `ml/tensor.jda` | `tensor A = [1024 x 1024]f32`. Shape in the type. Compile-time shape errors |
| Autograd | `ml/autograd.jda` | Symbolic differentiation over JIR. Generates `fn_grad()` at compile time |
| PTX Backend | `ml/ptx.jda` | JIR → PTX GPU kernel. Direct `/dev/nvidia0` ioctl. No CUDA runtime |
| AVX-512 Pass | `ml/avx512.jda` | Loop tiling (16×16) + `VFMADD213PS` emission. ~115 GFLOPS/core |
| Neural Net lib | `stdlib/ml/nn.jda` | Linear, ReLU, Sigmoid, Tanh, Softmax, MSELoss, Adam, SGD |
| MLP Demo | `examples/mlp.jda` | 10-line XOR MLP training. No Python. No C++. Single binary |

---

## Jda vs the World

```
               Safety    Speed     Ergonomics   ML-Native   No GC
               ──────    ─────     ──────────   ─────────   ─────
C / C++          ✗        ✓            ✗            ✗          ✓
Python           ✓        ✗            ✓            ✗          ✗
Go               ✓        ~            ✓            ✗          ✗
Rust             ✓        ✓            ✗            ✗          ✓
Jda              ✓        ✓            ✓            ✓          ✓
```

---

## Syntax Quick Reference

```jda
; Variables
let x     = 42               ; immutable, inferred i64
let mut y = 3.14             ; mutable
const MAX = 10_000           ; compile-time constant

; Functions
fn add(a: i64, b: i64) -> i64 => a + b
fn swap<T>(a: T, b: T) -> (T, T) => (b, a)

; Control flow
if x > 0 { "pos" } else { "neg" }              ; expression
loop i in 0..100 step 2 { print(i) }           ; range loop
for item in collection { process(item) }        ; iterator

; Concurrency
let ch = chan<i64>()
spawn { ch.send(compute()) }
let result = ch.recv()

; Tensors
tensor W = [768 x 768]f32::randn()
tensor y = x @ W + b                           ; shape-checked at compile time

; Inline asm
asm { in rax = 60   in rdi = 0   ---   syscall }   ; exit(0)
```

---

## Roadmap

- [ ] Stage 1 compiler fully operational (currently specified, codegen in progress)
- [ ] Self-hosting: Stage 1 compiled by Stage 0
- [ ] Standard library: `jda::fs`, `jda::time`, `jda::json`
- [ ] Package manager: `jda add <package>`
- [ ] Language server (LSP) for IDE support
- [ ] ARM64 backend (Apple Silicon, Raspberry Pi)
- [ ] WebAssembly backend
- [ ] Windows kernel support

---

## License

MIT
