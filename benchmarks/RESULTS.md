# Jda Benchmark Results

**Date**: April 8, 2026
**Platform**: Docker (Ubuntu 22.04, linux/amd64) on macOS Apple Silicon — all languages tested in the same containerized environment for fair comparison
**Methodology**: Best of 3 runs, wall-clock time via `time.perf_counter()`, no warm-up cache tricks

## Compilers Tested

| Language | Compiler | Version |
|----------|----------|---------|
| C | gcc | -O2 |
| Jda | jda1 | Stage 1 bootstrap |
| Rust | rustc | -O (release) |
| Go | go build | default |
| Python | python3 | 3.10 (interpreted) |
| Ruby | ruby | 3.0 (interpreted) |

---

## Runtime Performance (ms, lower is better)

| Benchmark | C | **Jda** | Rust | Go | Python | Ruby |
|-----------|----:|--------:|------:|-----:|-------:|-----:|
| sieve 1M | 27 | **24** | 31 | 32 | 416 | 408 |
| matmul 200x200 | 30 | 37 | 32 | 40 | 2,265 | 998 |
| sum 100M | 57 | **49** | 30 | 80 | 8,183 | 3,615 |
| fib(35) | 40 | 148 | 62 | 126 | 2,826 | 1,318 |
| json parse 50K | 32 | **31** | 33 | 90 | 159 | 342 |

### Key Takeaways — Runtime

- **JSON Parse**: Jda is the **fastest** at 31ms — beating C (32ms), Rust (33ms), Go (90ms). Scans 1.2 MB of generated JSON, extracts and sums 50K integer values. Jda's tight byte-scanning loop generates optimal native code.
- **Sieve of Eratosthenes**: Jda is the **fastest** — beating C (0.89x), Go (0.75x), and Rust (0.77x). The byte-array sieve maps perfectly to Jda's native memory model.
- **Matrix Multiply**: Jda is **1.2x C** and **0.93x Go** — competitive with systems languages for cache-friendly workloads.
- **Sum Loop**: Jda **beats C** (0.86x) and Go (0.61x) — NOP fallthrough pass + ADD imm8 encoding + loop register promotion make Jda's tight loop faster than gcc -O2.
- **Fibonacci**: Jda is **3.7x C** — recursive function call overhead is the main cost. Still **19x faster than Python** and **9x faster than Ruby**.
- **Average vs Python**: Jda is **~54x faster** across all benchmarks.
- **Average vs Ruby**: Jda is **~28x faster** across all benchmarks.
- **Jda beats C on 3 of 5 benchmarks** (json, sieve, sum) and beats Go on 4 of 5.

---

## Compilation Speed (ms, lower is better)

| Benchmark | C (gcc) | **Jda** | Rust | Go |
|-----------|--------:|--------:|------:|----:|
| sieve 1M | 479 | **45** | 1,579 | 658 |
| matmul 200x200 | 478 | **42** | 1,628 | 695 |
| sum 100M | 434 | **40** | 1,209 | 678 |
| fib(35) | 495 | **42** | 1,269 | 746 |
| json parse 50K | 510 | **48** | 1,726 | 789 |

### Key Takeaways — Compilation

- **Jda compiles 11-33x faster** than any other compiled language tested.
- Average: **43ms** vs gcc 479ms (11x), Go 713ms (16x), Rust 1,482ms (33x).
- Jda's single-pass compiler produces native x86-64 ELF binaries directly — no linker, no intermediate representation, no optimization passes.
- This makes Jda ideal for **rapid iteration** and **scripting-speed development** with compiled-language performance.

---

## Binary Size (bytes)

| Benchmark | C | **Jda** | Rust | Go |
|-----------|------:|--------:|---------:|----------:|
| sieve 1M | 16,064 | 1,049,935 | 3,954,520 | 1,763,478 |
| matmul 200x200 | 16,088 | 1,050,432 | 3,955,464 | 1,763,670 |
| sum 100M | 16,008 | 1,049,093 | 3,954,552 | 1,763,350 |
| fib(35) | 16,000 | 1,049,328 | 3,954,712 | 1,763,407 |
| json parse 50K | 16,104 | 1,054,086 | 3,958,296 | 2,230,683 |

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
| Runtime | 27–57ms | 24–148ms | **Jda wins 3 of 5** (json, sieve, sum) |
| Compilation | 479ms avg | **43ms avg (11x faster)** | Jda wins |
| Binary size | 16 KB (dynamic) | 1 MB (static) | C wins (but dynamically linked) |
| Dependencies | Needs gcc + libc | **Zero — bootstrapped from assembly** | Jda wins |
| Ecosystem | Mature | Growing (114 stdlib packages) | C wins |

### Jda vs Rust
| Metric | Rust | Jda | Verdict |
|--------|------|-----|---------|
| Runtime | 30–62ms | 24–148ms | **Jda wins 2 of 5** (json, sieve) |
| Compilation | 1,482ms avg | **43ms avg (33x faster)** | Jda wins |
| Binary size | 3.95 MB | **1.05 MB (3.8x smaller)** | Jda wins |
| Learning curve | Steep (borrow checker) | **Simple — no lifetimes, no borrow checker** | Jda wins |
| Safety | Memory safe | Manual memory | Rust wins |

### Jda vs Go
| Metric | Go | Jda | Verdict |
|--------|-----|-----|---------|
| Runtime | 32–126ms | 24–148ms | **Jda wins 4 of 5** (json, sieve, sum, matmul) |
| Compilation | 713ms avg | **43ms avg (16x faster)** | Jda wins |
| Binary size | 1.76 MB | **1.05 MB (40% smaller)** | Jda wins |
| Concurrency | Goroutines + channels | J-Threads + channels | Comparable |
| GC | Yes (pause risk) | **No GC** | Jda wins |

### Jda vs Python
| Metric | Python | Jda | Verdict |
|--------|--------|-----|---------|
| Runtime | 159–8,183ms | **24–148ms (54x faster avg)** | Jda wins |
| Startup | ~30ms interpreter | **<1ms native binary** | Jda wins |
| Typing | Dynamic | Static | Different trade-offs |
| Ecosystem | Massive (PyPI) | Growing (114 packages) | Python wins |

### Jda vs Ruby
| Metric | Ruby | Jda | Verdict |
|--------|------|-----|---------|
| Runtime | 342–3,615ms | **24–148ms (28x faster avg)** | Jda wins |
| Startup | ~50ms interpreter | **<1ms native binary** | Jda wins |
| Syntax | Elegant | Clean, C-like | Comparable |
| Ecosystem | Mature (gems) | Growing (114 packages) | Ruby wins |

---

## Why Use Jda?

1. **Beats C on 3 of 5 benchmarks** — Jda's optimized codegen outperforms gcc -O2 on JSON parse, sieve, and sum loop. Competitive on all workloads.

2. **Fastest compiler in the benchmark** — 11-33x faster than gcc, Go, or Rust. Edit-compile-run cycles feel instant.

3. **54x faster than Python, 28x faster than Ruby** — compiled performance with scripting-speed iteration.

4. **Zero dependencies** — Bootstrapped entirely from assembly. No C compiler, no runtime, no GC. A single static binary runs anywhere on Linux x86-64.

5. **Small binaries** — 1 MB self-contained executables. Smaller than Go (1.7 MB) and Rust (3.9 MB).

6. **Simple language** — No borrow checker, no lifetimes, no complex type system. If you know C, you know Jda.

7. **Growing standard library** — 114 packages covering strings, collections, networking, crypto, compression, and more.

8. **Self-hosted** — The compiler compiles itself. Proven bootstrap chain from raw x86-64 assembly to high-level language.

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
| **sieve 1M** | Sieve of Eratosthenes to 1,000,000 | Tests array access + branching |
| **matmul 200x200** | Dense matrix multiplication | Tests nested loops + memory access patterns |
| **sum 100M** | Sum integers 0..100,000,000 | Tests tight loop + integer arithmetic |
| **fib(35)** | Naive recursive Fibonacci | Tests function call overhead |
| **json parse 50K** | Generate + parse 1.2 MB JSON (50K objects) | Tests byte scanning + string generation |

Source code: [`benchmarks/`](benchmarks/) — identical algorithms in C, Go, Rust, Jda, Python, Ruby.
