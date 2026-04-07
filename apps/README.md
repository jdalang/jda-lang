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
