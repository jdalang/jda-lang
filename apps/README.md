# Jda Applications

Real-world applications written entirely in Jda, demonstrating the language's capabilities for production use.

## jda-grep

A high-performance text search tool — Jda's first real application.

### Features

- Pattern matching (substring search)
- Case-insensitive search (`-i`)
- Line numbers (`-n`)
- Match count (`-c`)
- Invert match (`-v`)
- List matching files only (`-l`)
- Multi-file search with filename prefixes
- Stdin piping support
- ANSI color output (disable with `--no-color`)
- Combined short flags (`-ni`, `-cv`, etc.)
- Proper exit codes (0 = match found, 1 = no match, 2 = error)

### Build

```bash
bash apps/build-grep.sh
```

### Usage

```bash
# Search for pattern in file
./apps/jda-grep error log.txt

# Case-insensitive with line numbers
./apps/jda-grep -ni TODO main.jda

# Count matches across multiple files
./apps/jda-grep -c "fn " stdlib/*.jda

# List files containing pattern
./apps/jda-grep -l bug *.jda

# Pipe from stdin
cat server.log | ./apps/jda-grep "500 Internal"

# Show non-matching lines
./apps/jda-grep -v "^;" config.jda
```

### Binary Size

~1.05 MB static ELF binary. Zero external dependencies.

### Dependencies

Uses only Jda stdlib: `prelude.jda`, `fs.jda`, `file_io.jda` (~636 lines of library code).

## jda-ml-demo

Neural network training benchmark — Jda vs Python head-to-head comparison. Trains MLPs from scratch with no external dependencies on either side.

### Tasks

| # | Task | Architecture | Epochs |
|---|------|-------------|--------|
| 1 | XOR Classification | 2→8→1 MLP | 5,000 |
| 2 | Sine Approximation | 1→16→1 MLP | 10,000 |
| 3 | Matrix Multiply | 64×64 matmul | 10 iters |

### Performance (x86-64 Linux)

| Task | Jda | Python (no NumPy) | Speedup |
|------|-----|-------------------|---------|
| XOR training | 35 ms | 407 ms | **~12x** |
| Sine training | 512 ms | 7,839 ms | **~15x** |
| 64×64 matmul | 2.5 ms | 35 ms | **~14x** |

Both implementations use identical algorithms (same loop structure, same SGD, same loss function). The only difference is the runtime: Jda compiles to native x86-64 machine code, Python interprets through CPython.

### Build & Run

```bash
# Build Jda binary
bash apps/build-ml-demo.sh

# Run Jda only (in Docker)
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v $(PWD):/jda -w /jda jda-build ./apps/jda-ml-demo

# Run Python only
python3 apps/ml-demo-python.py

# Run both side by side with comparison
bash apps/run-ml-benchmark.sh
```

### Binary Size

~1.08 MB static ELF binary. Zero external dependencies.

### Dependencies

Jda: only `time.jda` for benchmarking. All tensor/f64 operations are compiler builtins.
Python: only stdlib (`math`, `time`, `random`). No NumPy.
