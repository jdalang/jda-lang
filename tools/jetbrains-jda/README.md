# Jda Language Plugin for JetBrains IDEs

IntelliJ IDEA / CLion / WebStorm / etc. plugin for the Jda programming language.

## Features

- **Syntax highlighting** — keywords, types, strings, numbers, operators, builtins
- **LSP integration** — go-to-definition, hover, diagnostics, completion via `jda-lsp`
- **Bracket matching** — braces `{}`, brackets `[]`, parentheses `()`
- **Code folding** — fold function bodies and struct definitions
- **Commenter** — toggle line comments with `;`
- **Color settings** — customizable colors under Settings > Editor > Color Scheme > Jda

## Requirements

- IntelliJ IDEA 2024.1+ (or any JetBrains IDE based on IntelliJ Platform 241+)
- Java 17+
- `jda-lsp.sh` for LSP features (auto-detected from project `tools/` or PATH)

## Building

```bash
cd tools/jetbrains-jda
./gradlew buildPlugin
```

The plugin ZIP will be in `build/distributions/`.

## Installing

1. Build the plugin (see above)
2. In your JetBrains IDE: Settings > Plugins > ⚙️ > Install Plugin from Disk
3. Select the `.zip` from `build/distributions/`
4. Restart the IDE

## Development

```bash
# Run a sandboxed IDE instance with the plugin loaded
./gradlew runIde

# Run tests
./gradlew test
```

## LSP Configuration

The plugin auto-detects `jda-lsp.sh` in:
1. `<project-root>/tools/jda-lsp.sh`
2. `jda-lsp` or `jda-lsp.sh` on PATH

If not found, LSP features will be unavailable. Ensure `jda-lsp.sh` is
executable and on your PATH.
