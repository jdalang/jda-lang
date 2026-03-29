# Jda — Vision & Design Philosophy

## The Problem

The modern software landscape forces developers into a trilemma — sacrifice performance, safety, or ergonomics:

- **C/C++**: Raw performance, but unsafe memory (70% of security vulnerabilities) and dependency hell
- **Python**: Great ergonomics, but it's just glue over C++ libraries (PyTorch, TensorFlow)
- **Go**: Easy concurrency, but GC pauses make it unsuitable for real-time systems
- **Rust**: Safe and fast, but steep learning curve and slow compile times

## The Solution

Jda resolves the trilemma by building from first principles:

### 1. Kernel-Level Independence (Replace C)

Jda does not link against libc. It issues direct system calls to the kernel. This produces static, conflict-free binaries that run anywhere without installing libraries — eliminating the entire class of "dependency hell" bugs.

### 2. Native ML Compilation (Replace Python)

Instead of being a "glue" language that calls C++ libraries:

- **First-class tensors**: `Tensor` is a primitive type, not a class
- **Compile-time autograd**: The compiler understands calculus and generates backward passes at compile time, eliminating runtime graph overhead
- **Direct GPU compilation**: Jda compiles tensor operations to PTX (NVIDIA) and ROCm without going through CUDA's C++ runtime
- **Hardware intrinsics**: SIMD/AVX-512 instructions generated automatically from high-level map/reduce code

### 3. Deterministic Concurrency (Replace Go)

Jda adopts Go's "easy concurrency" philosophy but replaces the garbage collector:

- **Actor model**: Each actor has private memory — no shared state, no data races
- **J-Threads**: Lightweight green threads (like goroutines) with M:N scheduling
- **Zero-copy message passing**: Ownership transfer between actors is a pointer move, not a copy
- **Lock-free channels**: Built-in message-passing syntax

### 4. Expressive Syntax (Match Ruby)

Clean, block-based syntax with minimal boilerplate:

- No unnecessary semicolons
- Pattern matching and Result types (no exceptions)
- Compile-time metaprogramming for DSL capabilities
- Ruby's expressiveness compiled to native machine code

## Memory Management

Jda uses a hybrid model — no GC, no manual malloc/free:

1. **Compile-Time Reference Counting (CTRC)**: The compiler inserts and optimizes reference counting at compile time, eliminating 95% of runtime overhead through static analysis
2. **Region-based allocation (Arenas)**: For hot paths — allocation is a pointer bump, deallocation is O(1)
3. **Linear types for resources**: Files, sockets, and handles must be consumed exactly once — the compiler prevents resource leaks

## JIR — Jda Intermediate Representation

Instead of depending on LLVM (written in C++), Jda builds its own SSA-based IR:

- Designed for both CPU vectorization and GPU kernel generation
- Optimization passes written in Jda itself (constant folding, DCE, loop tiling)
- Targets x86-64 natively, with planned PTX and ARM64 backends

## Bootstrap Philosophy

Jda is built with zero external language dependencies:

```
Stage 0: Hand-written x86-64 assembly (jda0) — the seed
Stage 1: Real compiler written in Jda (jda1) — compiled by jda0
Self-host: jda1 compiles itself — C/C++ officially eliminated
```

This is not just a technical choice — it's a statement that a modern systems language can exist without standing on C's shoulders.

## Target Use Cases

- **Systems programming**: OS kernels, drivers, embedded systems
- **ML/AI**: Training loops, custom kernels, inference engines — all native
- **High-performance servers**: HTTP, WebSocket, database engines with deterministic latency
- **Real-time systems**: Games, trading, robotics — no GC pauses
