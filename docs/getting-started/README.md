# Getting Started with Jda

Hands-on guides that take you from zero to a working program.

## Step 1: Install

**[Installation Guide](installation.md)** — Windows `.exe`, macOS `.pkg`, Linux `.deb`/`.rpm`, or shell script.

## Step 2: Build Something

| Guide | What you build | Key concepts |
|-------|---------------|--------------|
| [Build a CLI Tool](cli-tool.md) | `jwc` — a word-count tool like Unix `wc` | Args parsing, file I/O, `for` loops, `+=` |
| [Build an HTTP Server](http-server.md) | Static file server on port 8080 | Raw syscalls, TCP sockets, byte manipulation |
| [Train a Neural Network](ml-example.md) | 2→8→1 MLP that learns XOR | `f64` floats, arrays, math, backpropagation |

All three guides produce static ELF binaries under 1.1 MB with zero external dependencies.

## After the guides

- [Language Syntax Reference](../language/syntax.md)
- [Stdlib API Docs](../stdlib-md/)
- [Toolchain Reference](../language/toolchain.md)
- [Example Programs](../../examples/)
- [Real Applications](../../apps/) (jda-grep, ML benchmark)
