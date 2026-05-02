# Jda Language Extension for VS Code

Syntax highlighting, code intelligence, and formatting for the Jda programming language.

## Features

- **Syntax Highlighting** — keywords, types, builtins, strings, numbers, comments
- **Go-to-Definition** — jump to fn/struct/enum/const declarations
- **Hover** — documentation for keywords and user-defined functions
- **Completion** — keywords, symbols, and variables in scope
- **Document Symbols** — outline view (fn, struct, enum, const, impl)
- **Formatting** — 4-space indent normalization
- **Diagnostics** — tab and trailing whitespace warnings

## Installation

### Option 1: Install from source (development)

```bash
# From the repo root
cd tools/vscode-jda
npm install
code --install-extension .
```

### Option 2: Symlink for development

```bash
# Link the extension into VS Code's extensions directory
ln -s $(pwd)/tools/vscode-jda ~/.vscode/extensions/jda-lang
```

Then reload VS Code (`Cmd+Shift+P` → "Developer: Reload Window").

## Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| `jda.lsp.enabled` | `true` | Enable the Jda Language Server |
| `jda.lsp.path` | `""` | Path to `jda-lsp.sh` (auto-detected if empty) |

The LSP server is auto-detected from `tools/jda-lsp.sh` in the workspace root.
To override, set `jda.lsp.path` in your VS Code settings:

```json
{
    "jda.lsp.path": "/path/to/jda-lang/tools/jda-lsp.sh"
}
```

## Requirements

- Python 3.6+ (for the LSP server)
- VS Code 1.75+

## File Association

The extension automatically associates `.jda` files with the Jda language.
