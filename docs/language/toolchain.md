# Jda Toolchain Reference

Jda ships a unified CLI (`tools/jda`) with 13+ subcommands covering the full development lifecycle.

## CLI Commands

```bash
jda build <file.jda>              # Compile to native binary
jda build --safe <file.jda>       # Compile with unsafe block enforcement
jda build --include <lib> <file>  # Compile with stdlib includes
jda run <file.jda>                # Compile and execute
jda repl                          # Interactive REPL
jda test <dir/>                   # Run conformance tests
jda fmt <file.jda>                # Format source code
jda doc <file.jda>                # Generate HTML documentation
jda doc --json <file.jda>         # Generate doc data as JSON
jda pkg <subcommand>              # Package manager
jda bench <file.jda>              # Run benchmarks
jda fuzz <file.jda>               # Fuzz test targets
jda race <file.jda>               # Race condition detection
jda lsp                           # Language Server Protocol
jda wasm <file.jda>               # Compile to WebAssembly
jda arm64 <file.jda>              # Cross-compile to ARM64
```

## Package Manager (`jda pkg`)

```bash
jda pkg init                      # Create jda.toml manifest
jda pkg add <name> <url> [tag]    # Add git dependency
jda pkg remove <name>             # Remove dependency
jda pkg update [name]             # Update dependencies
jda pkg build                     # Resolve deps and compile
jda pkg run                       # Build and execute
jda pkg deps                      # List resolved dependencies
jda pkg tree                      # Show dependency tree
jda pkg check                     # Verify manifest and lockfile
jda pkg install <name>            # Install stdlib package to lib/
jda pkg list                      # List installed packages
jda pkg clean                     # Remove build artifacts
jda pkg search [query]            # Search stdlib packages
```

### Manifest (`jda.toml`)

```toml
[package]
name = "myapp"
version = "0.1.0"

[build]
entry = "src/main.jda"
output = "build/myapp"

[dependencies]
mylib = { git = "https://github.com/user/mylib", tag = "v1.0" }
```

## Documentation Generator (`jda doc`)

Doc comments use `;;` prefix:

```jda
;; Calculate the distance between two points.
;; Returns the squared Euclidean distance.
fn distance(a: &Point, b: &Point) -> i64 {
    let dx = b.x - a.x
    let dy = b.y - a.y
    ret dx * dx + dy * dy
}
```

Generate docs:

```bash
jda doc stdlib/                   # HTML docs for all stdlib files
jda doc --output docs/ src/       # Specify output directory
jda doc --json file.jda           # JSON output for tooling
```

## Benchmarking (`jda bench`)

Write benchmark functions prefixed with `bench_`:

```jda
fn bench_fib(n: i64) {
    let i = 0
    loop i < n { fib(25)  i = i + 1 }
}
```

Run:

```bash
jda bench mylib.jda               # Auto-calibrate iterations
jda bench --count 1000 mylib.jda  # Fixed iteration count
jda bench --json mylib.jda        # JSON output
jda bench --compare base.json mylib.jda  # Compare against baseline
```

Output (Go-style):

```
bench_fib       1000    12345 ns/op
```

## Testing (`jda test`)

Conformance tests use `.jda` + `.expected` pairs:

```
tests/conformance/stage1/pass/my_test.jda
tests/conformance/stage1/pass/my_test.expected
```

The test runner compiles each `.jda` file, runs it, and compares stdout against `.expected`.

```bash
jda test tests/conformance/       # Run all tests
```

## Fuzzing (`jda fuzz`)

Write fuzz targets prefixed with `fuzz_`:

```jda
fn fuzz_parser(data: &i8, len: i64) {
    parse(data, len)
}
```

```bash
jda fuzz mylib.jda                # Start fuzzing
```

## Race Detection (`jda race`)

Detects data races in concurrent programs:

```bash
jda race myapp.jda                # Epoch-based happens-before analysis
```

## Building from Source

```bash
# Build Docker image (once)
docker build -t jda-build docker/

# Build jda1 compiler
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v $(PWD):/jda -w /jda/bootstrap/stage0 jda-build make stage1

# Verify self-hosting convergence
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v $(PWD):/jda -w /jda/bootstrap/stage0 jda-build make selfhost
```
