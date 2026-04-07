# Jda Benchmark Results

**Date**: April 7, 2026
**Platform**: Linux x86-64 (Docker, Ubuntu 22.04)
**Methodology**: Best of 3 runs, wall-clock time, no warm-up cache tricks

## Compilers Tested

| Language | Compiler | Version |
|----------|----------|---------|
| C | gcc | -O2 |
| Go | go build | default |
| Rust | rustc | -O (release) |
| Jda | jda1 | Stage 1 bootstrap |
| Python | python3 | 3.10 (interpreted) |
| Ruby | ruby | 3.0 (interpreted) |

---

## Runtime Performance (ms, lower is better)

| Benchmark | C | Go | Rust | **Jda** | Python | Ruby |
|-----------|----:|-----:|------:|--------:|-------:|-----:|
| fib(35) | 41 | 127 | 63 | **156** | 2,829 | 1,288 |
| sieve 1M | 27 | 32 | 31 | **23** | 442 | 388 |
| sum 100M | 26 | 79 | 29 | **283** | 8,005 | 3,594 |
| matmul 200x200 | 29 | 40 | 31 | **47** | 2,295 | 988 |

### Key Takeaways — Runtime

- **Sieve of Eratosthenes**: Jda is the **fastest** — beating C (0.85x), Go (0.72x), and Rust (0.74x). The byte-array sieve maps perfectly to Jda's native memory model.
- **Matrix Multiply**: Jda is **1.6x C** and **1.2x Go** — competitive with systems languages for cache-friendly workloads.
- **Fibonacci**: Jda is **3.8x C** — recursive function call overhead is the main cost. Still **18x faster than Python** and **8x faster than Ruby**.
- **Sum Loop**: Jda is **10.9x C** — tight integer loops expose lack of loop optimizations. But still **28x faster than Python** and **12.7x faster than Ruby**.
- **Average vs Python**: Jda is **~24x faster** across all benchmarks.
- **Average vs Ruby**: Jda is **~12x faster** across all benchmarks.

---

## Compilation Speed (ms, lower is better)

| Benchmark | C (gcc) | Go | Rust | **Jda** |
|-----------|--------:|----:|------:|--------:|
| fib(35) | 555 | 804 | 1,339 | **45** |
| sieve 1M | 474 | 683 | 1,580 | **47** |
| sum 100M | 390 | 669 | 1,207 | **40** |
| matmul 200x200 | 464 | 667 | 1,596 | **43** |

### Key Takeaways — Compilation

- **Jda compiles 10-37x faster** than any other compiled language tested.
- Average: **44ms** vs gcc 471ms (10.7x), Go 706ms (16x), Rust 1,431ms (32.5x).
- Jda's single-pass compiler produces native x86-64 ELF binaries directly — no linker, no intermediate representation, no optimization passes.
- This makes Jda ideal for **rapid iteration** and **scripting-speed development** with compiled-language performance.

---

## Binary Size (bytes)

| Benchmark | C | Go | Rust | **Jda** |
|-----------|------:|----------:|---------:|--------:|
| fib(35) | 16,000 | 1,763,407 | 3,954,712 | **1,049,397** |
| sieve 1M | 16,064 | 1,763,478 | 3,954,520 | **1,050,257** |
| sum 100M | 15,968 | 1,763,350 | 3,954,552 | **1,049,189** |
| matmul 200x200 | 16,088 | 1,763,670 | 3,955,464 | **1,050,860** |

### Key Takeaways — Binary Size

- C produces the smallest binaries (~16 KB) due to dynamic linking against libc.
- Jda binaries are **~1 MB** — statically linked, zero external dependencies.
- Go binaries are **1.7 MB**, Rust binaries are **3.9 MB** — both larger than Jda.
- Jda binaries are **self-contained ELF executables** with no runtime, no GC, no standard library linked in.

---

## Jda vs Each Language — Summary

### Jda vs C
| Metric | C | Jda | Verdict |
|--------|---|-----|---------|
| Runtime | Fastest overall | 0.85x–10.9x slower | C wins on raw speed |
| Compilation | 471ms avg | **44ms avg (10.7x faster)** | Jda wins |
| Binary size | 16 KB (dynamic) | 1 MB (static) | C wins (but dynamically linked) |
| Dependencies | Needs gcc + libc | **Zero — bootstrapped from assembly** | Jda wins |
| Ecosystem | Mature | Growing (114 stdlib packages) | C wins |

### Jda vs Go
| Metric | Go | Jda | Verdict |
|--------|-----|-----|---------|
| Runtime | 1.0–3.0x slower than C | 0.85x–10.9x slower than C | Mixed |
| Compilation | 706ms avg | **44ms avg (16x faster)** | Jda wins |
| Binary size | 1.76 MB | **1.05 MB (40% smaller)** | Jda wins |
| Concurrency | Goroutines + channels | J-Threads + channels | Comparable |
| GC | Yes (pause risk) | **No GC** | Jda wins |

### Jda vs Rust
| Metric | Rust | Jda | Verdict |
|--------|------|-----|---------|
| Runtime | Near C speed | 0.85x–10.9x slower than C | Rust wins on raw speed |
| Compilation | 1,431ms avg | **44ms avg (32.5x faster)** | Jda wins |
| Binary size | 3.95 MB | **1.05 MB (3.8x smaller)** | Jda wins |
| Learning curve | Steep (borrow checker) | **Simple — no lifetimes, no borrow checker** | Jda wins |
| Safety | Memory safe | Manual memory | Rust wins |

### Jda vs Python
| Metric | Python | Jda | Verdict |
|--------|--------|-----|---------|
| Runtime | 442–8,005ms | **23–283ms (24x faster avg)** | Jda wins |
| Startup | ~30ms interpreter | **<1ms native binary** | Jda wins |
| Typing | Dynamic | Static | Different trade-offs |
| Ecosystem | Massive (PyPI) | Growing (114 packages) | Python wins |

### Jda vs Ruby
| Metric | Ruby | Jda | Verdict |
|--------|------|-----|---------|
| Runtime | 388–3,594ms | **23–283ms (12x faster avg)** | Jda wins |
| Startup | ~50ms interpreter | **<1ms native binary** | Jda wins |
| Syntax | Elegant | Clean, C-like | Comparable |
| Ecosystem | Mature (gems) | Growing (114 packages) | Ruby wins |

---

## Why Use Jda?

1. **Fastest compiler in the benchmark** — 10-37x faster than gcc, Go, or Rust. Edit-compile-run cycles feel instant.

2. **Competitive runtime performance** — Beats C on sieve, matches Go on matrix multiply, and is 12-24x faster than Python/Ruby.

3. **Zero dependencies** — Bootstrapped entirely from assembly. No C compiler, no runtime, no GC. A single static binary runs anywhere on Linux x86-64.

4. **Small binaries** — 1 MB self-contained executables. Smaller than Go (1.7 MB) and Rust (3.9 MB).

5. **Simple language** — No borrow checker, no lifetimes, no complex type system. If you know C, you know Jda.

6. **Growing standard library** — 114 packages covering strings, collections, networking, crypto, compression, and more.

7. **Self-hosted** — The compiler compiles itself. Proven bootstrap chain from raw x86-64 assembly to high-level language.

---

## Reproduce These Results

```bash
# Build the benchmark image
docker build --platform linux/amd64 -t jda-bench benchmarks/

# Run all benchmarks
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v $(pwd):/jda -w /jda jda-bench bash /jda/benchmarks/run.sh
```

Results are saved to `benchmarks/results.csv`.

## Benchmark Programs

All benchmarks implement identical algorithms across all languages:

| Benchmark | Description | Complexity |
|-----------|-------------|------------|
| **fib(35)** | Naive recursive Fibonacci | Tests function call overhead |
| **sieve 1M** | Sieve of Eratosthenes to 1,000,000 | Tests array access + branching |
| **sum 100M** | Sum integers 0..100,000,000 | Tests tight loop + integer arithmetic |
| **matmul 200x200** | Dense matrix multiplication | Tests nested loops + memory access patterns |

Source code: [`benchmarks/`](benchmarks/) — identical algorithms in C, Go, Rust, Jda, Python, Ruby.
