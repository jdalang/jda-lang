# Installation Guide

## Quick Install

Pick the installer for your platform:

| Platform | Download | How to install |
|----------|----------|---------------|
| **Windows 10/11** | [`.exe` installer](https://github.com/jdalang/jda-lang/releases/latest) | Double-click, follow wizard |
| **macOS** | [`.pkg` installer](https://github.com/jdalang/jda-lang/releases/latest) | Double-click, follow prompts |
| **Ubuntu / Debian** | [`.deb` package](https://github.com/jdalang/jda-lang/releases/latest) | `sudo dpkg -i jda_0.2.0_amd64.deb` |
| **Fedora / RHEL / CentOS** | [`.rpm` package](https://github.com/jdalang/jda-lang/releases/latest) | `sudo rpm -i jda-0.2.0-1.x86_64.rpm` |
| **Arch Linux** | Tarball | [Manual install](#linux-tarball) |
| **FreeBSD** | Tarball | [Manual install](#freebsd) |

After installation, verify:

```bash
jda version
```

---

## Windows

### Option 1: .exe Installer (recommended)

1. Download `jda-0.2.0-windows-setup.exe` from the [releases page](https://github.com/jdalang/jda-lang/releases/latest)
2. Double-click to run the installer
3. Follow the installation wizard
4. Open a new Command Prompt or PowerShell and run:

```cmd
jda version
```

The installer adds `jda` to your system PATH automatically.

**Requirements:** WSL2 or Docker Desktop. Jda compiles to Linux x86-64 binaries, so it needs a Linux environment on Windows.

If you don't have WSL2:

```cmd
wsl --install
```

Restart your computer after WSL2 installs.

### Option 2: PowerShell script

```powershell
irm https://raw.githubusercontent.com/jdalang/jda-lang/main/install.ps1 | iex
```

### Option 3: Inside WSL2 (native speed)

```bash
# Inside WSL2 terminal
curl -fsSL https://raw.githubusercontent.com/jdalang/jda-lang/main/install.sh | sh
```

This gives you native Linux performance. Recommended for development.

---

## macOS

### Option 1: .pkg Installer (recommended)

1. Download `jda-0.2.0-macos.pkg` from the [releases page](https://github.com/jdalang/jda-lang/releases/latest)
2. Double-click to open the installer
3. Follow the prompts (installs to `/usr/local/jda`)
4. Open Terminal and run:

```bash
jda version
```

**Requirements:** [Docker Desktop for Mac](https://docs.docker.com/desktop/install/mac-install/). Jda compiles to Linux x86-64 binaries, so Docker provides the compilation environment.

The installer will attempt to build the Docker image automatically. If Docker is not installed, `jda` will prompt you to install it on first use.

### Option 2: Shell script

```bash
curl -fsSL https://raw.githubusercontent.com/jdalang/jda-lang/main/install.sh | sh
```

Works on both Intel and Apple Silicon Macs.

### Option 3: Homebrew (coming soon)

```bash
brew install jdalang/tap/jda
```

---

## Ubuntu / Debian

### Option 1: .deb Package (recommended)

```bash
# Download
curl -LO https://github.com/jdalang/jda-lang/releases/latest/download/jda_0.2.0_amd64.deb

# Install
sudo dpkg -i jda_0.2.0_amd64.deb

# Verify
jda version
```

To uninstall:

```bash
sudo dpkg -r jda
```

### Option 2: Shell script

```bash
curl -fsSL https://raw.githubusercontent.com/jdalang/jda-lang/main/install.sh | sh
```

---

## Fedora / RHEL / CentOS

### Option 1: .rpm Package (recommended)

```bash
# Download
curl -LO https://github.com/jdalang/jda-lang/releases/latest/download/jda-0.2.0-1.x86_64.rpm

# Install
sudo rpm -i jda-0.2.0-1.x86_64.rpm

# Verify
jda version
```

To uninstall:

```bash
sudo rpm -e jda
```

### Option 2: Shell script

```bash
curl -fsSL https://raw.githubusercontent.com/jdalang/jda-lang/main/install.sh | sh
```

---

## Linux Tarball

For any Linux distribution (Arch, Alpine, Gentoo, NixOS, etc.):

```bash
# Download
curl -LO https://github.com/jdalang/jda-lang/releases/latest/download/jda-0.2.0-linux-x86_64.tar.gz

# Extract
mkdir -p ~/.jda
tar -xzf jda-0.2.0-linux-x86_64.tar.gz -C ~/.jda

# Add to PATH
echo 'export PATH="$HOME/.jda/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verify
jda version
```

---

## FreeBSD

Jda runs on FreeBSD x86-64 via Linux binary compatibility:

```bash
# Enable Linux compatibility
sudo sysctl kern.elf64.fallback_brand=3

# Then install via tarball
curl -LO https://github.com/jdalang/jda-lang/releases/latest/download/jda-0.2.0-linux-x86_64.tar.gz
mkdir -p ~/.jda
tar -xzf jda-0.2.0-linux-x86_64.tar.gz -C ~/.jda
echo 'export PATH="$HOME/.jda/bin:$PATH"' >> ~/.profile
```

---

## ChromeOS

Enable the Linux development environment (Crostini), then use the Linux installer:

```bash
curl -fsSL https://raw.githubusercontent.com/jdalang/jda-lang/main/install.sh | sh
```

---

## Installer Options

The shell installer supports environment variables:

```bash
# Install a specific version
JDA_VERSION=0.2.0 curl -fsSL .../install.sh | sh

# Custom install directory (default: ~/.jda)
JDA_INSTALL_DIR=/opt/jda curl -fsSL .../install.sh | sh

# Skip PATH modification
JDA_NO_MODIFY_PATH=1 curl -fsSL .../install.sh | sh
```

---

## Uninstall

### Native installers

| Platform | Uninstall |
|----------|-----------|
| Windows | Control Panel → Programs → Uninstall "Jda Programming Language" |
| macOS | `sudo rm -rf /usr/local/jda /usr/local/bin/jda` |
| Ubuntu/Debian | `sudo dpkg -r jda` |
| Fedora/RHEL | `sudo rpm -e jda` |

### Shell installer

```bash
curl -fsSL https://raw.githubusercontent.com/jdalang/jda-lang/main/install.sh | sh -s -- --uninstall
```

Or manually:

```bash
rm -rf ~/.jda
# Remove the PATH line from your shell profile (~/.bashrc, ~/.zshrc, etc.)
```

---

## Verify Installation

```bash
# Check version
jda version

# Compile and run a test program
echo 'fn main() -> i64 { print("Hello from Jda!\n") ret 0 }' > hello.jda
jda run hello.jda
```

Expected output:

```
Hello from Jda!
```

---

## Troubleshooting

### "jda: command not found"

Your PATH may not include the jda binary. Add it:

```bash
# For ~/.jda install
export PATH="$HOME/.jda/bin:$PATH"

# For system install (/usr/local)
export PATH="/usr/local/bin:$PATH"
```

Restart your terminal or run `source ~/.bashrc`.

### "Docker is not running" (macOS)

Jda on macOS requires Docker Desktop. Install it from:
https://docs.docker.com/desktop/install/mac-install/

Make sure Docker Desktop is running (whale icon in menu bar).

### "WSL2 not found" (Windows)

Install WSL2:

```cmd
wsl --install
```

Restart your computer, then try again.

### Permission denied on Linux

If you get permission errors during install:

```bash
# Install to home directory (no sudo needed)
curl -fsSL https://raw.githubusercontent.com/jdalang/jda-lang/main/install.sh | sh

# Or install system-wide
sudo dpkg -i jda_0.2.0_amd64.deb
```

---

## What Gets Installed

| Component | Description | Size |
|-----------|-------------|------|
| `jda1` | Compiler binary (static ELF) | ~2 MB |
| `stdlib/` | 114 standard library packages | ~400 KB |
| `tools/` | CLI, formatter, doc gen, LSP, pkg manager | ~50 KB |
| **Total** | | **~2.5 MB** |

Installation location:
- Shell installer: `~/.jda/`
- .deb / .rpm / .pkg: `/usr/local/jda/`
- Windows .exe: `C:\Program Files\Jda\`

---

## Next Steps

- [Build a CLI Tool](cli-tool.md)
- [Build an HTTP Server](http-server.md)
- [Train a Neural Network](ml-example.md)
- [Language Syntax Reference](../language/syntax.md)
