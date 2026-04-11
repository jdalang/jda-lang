# Installing Jda

Jda compiles to native Linux x86-64 binaries. On other platforms, it runs
via Docker or WSL2 for compilation, producing the same Linux ELF output.

## Quick Install

### Linux / macOS / WSL2 / FreeBSD

```bash
curl -fsSL https://raw.githubusercontent.com/jdalang/jda-lang/main/install.sh | sh
```

### Windows (PowerShell 5+)

```powershell
irm https://raw.githubusercontent.com/jdalang/jda-lang/main/install.ps1 | iex
```

### Windows (CMD fallback)

```cmd
curl -o install.bat https://raw.githubusercontent.com/jdalang/jda-lang/main/install.bat
install.bat
```

## Platform Support

| Platform | Architecture | Method | Notes |
|----------|-------------|--------|-------|
| Ubuntu/Debian | x86-64 | Native | Best performance, no dependencies |
| Ubuntu/Debian | ARM64 | Docker | `apt install docker.io` |
| Fedora/RHEL | x86-64 | Native | |
| Fedora/RHEL | ARM64 | Docker | `dnf install docker` |
| Alpine Linux | x86-64 | Native | Needs `libc6-compat` for glibc compat |
| macOS | Intel (x86-64) | Docker | Docker Desktop required |
| macOS | Apple Silicon (ARM64) | Docker | Docker Desktop with Rosetta |
| Windows 10/11 | x86-64 | WSL2 | Recommended: `wsl --install` |
| Windows 10/11 | x86-64 | Docker | Docker Desktop |
| Windows 10/11 | ARM64 | WSL2 | `wsl --install` (x86 emulation) |
| FreeBSD | x86-64 | Native | Linux binary compat layer required |
| ChromeOS | x86-64 | Linux (Crostini) | Enable Linux development environment |

## What Gets Installed

```
~/.jda/
  bin/
    jda              # CLI wrapper (sh/ps1/cmd)
    jda1             # Compiler binary (Linux x86-64 ELF)
  stdlib/            # 114 standard library packages
  tools/             # Development tools (formatter, docs, etc.)
  docker/            # Dockerfile for Docker-based compilation
  VERSION            # Installed version
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `JDA_HOME` | `~/.jda` | Installation directory |
| `JDA_INSTALL_DIR` | `~/.jda` | Override install location |
| `JDA_VERSION` | latest | Version to install |
| `JDA_NO_MODIFY_PATH` | 0 | Set to 1 to skip PATH changes |

### Custom Install Location

```bash
JDA_INSTALL_DIR=/opt/jda curl -fsSL .../install.sh | sh
```

```powershell
.\install.ps1 -InstallDir "C:\jda"
```

## Post-Install

After installation, restart your terminal or source your shell config:

```bash
# bash
source ~/.bashrc

# zsh
source ~/.zshrc

# fish
source ~/.config/fish/config.fish
```

Verify the installation:

```bash
jda version
```

## Usage

```bash
# Compile a program
jda build hello.jda -o hello

# Compile and run
jda run hello.jda

# Compile with stdlib package
jda build --include stdlib/json.jda myapp.jda -o myapp
```

## Docker Details

On non-Linux platforms, the `jda` wrapper uses Docker transparently:

1. First run builds a lightweight Docker image (`jda-build`, ~150MB)
2. Each `jda build` / `jda run` command runs in a container
3. Source files and output are mounted via volumes
4. The container is removed after each run (stateless)

### Manual Docker Setup

If the automatic image build fails:

```bash
docker build --platform=linux/amd64 -t jda-build - << 'EOF'
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y nasm binutils make xxd file python3 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /jda
CMD ["/bin/bash"]
EOF
```

### Direct Docker Usage (without installer)

```bash
docker run --rm --platform linux/amd64 \
  --ulimit stack=524288000:524288000 \
  -v $(PWD):/jda -w /jda \
  jda-build \
  /jda/bootstrap/stage1/jda1 build hello.jda -o hello
```

## WSL2 Setup (Windows)

1. Install WSL2:
   ```powershell
   wsl --install
   ```

2. Restart your computer.

3. Open Ubuntu from Start menu and run:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/jdalang/jda-lang/main/install.sh | sh
   ```

4. Jda is now available inside WSL. To use from Windows PowerShell:
   ```powershell
   wsl jda version
   wsl jda run hello.jda
   ```

## Uninstall

### Linux / macOS

```bash
curl -fsSL .../install.sh | sh -s -- --uninstall
# or
rm -rf ~/.jda
```

### Windows

```powershell
.\install.ps1 -Uninstall
# or
Remove-Item -Recurse "$env:USERPROFILE\.jda"
```

## Building from Source

If you want to build the compiler from source instead of using pre-built binaries:

```bash
git clone https://github.com/jdalang/jda-lang.git
cd jda-lang

# Build Docker image
docker build --platform=linux/amd64 -t jda-build docker/

# Build stage 1 compiler
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v $(PWD):/jda -w /jda/bootstrap/stage0 jda-build make stage1

# Self-host verification
docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v $(PWD)/bootstrap:/jda -w /jda/stage0 jda-build sh -c \
  "./jda1 ../stage1/jda1.jda jda1_sh2 2>/dev/null && echo OK"
```

## Troubleshooting

### "Docker is not running"
Start Docker Desktop (macOS/Windows) or the Docker daemon (Linux):
```bash
sudo systemctl start docker
```

### "Permission denied" on Linux
Add your user to the docker group:
```bash
sudo usermod -aG docker $USER
# Log out and back in
```

### "jda: command not found" after install
Your PATH wasn't updated. Add manually:
```bash
export PATH="$HOME/.jda/bin:$PATH"
```

### Slow compilation on macOS/Windows
First compilation downloads the Docker image (~150MB). Subsequent compilations are fast.
Docker Desktop on macOS uses x86-64 emulation which adds ~2-3x overhead.

### WSL2 "wsl --install" fails
Ensure virtualization is enabled in BIOS/UEFI settings (Intel VT-x / AMD-V).
