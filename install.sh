#!/bin/sh
# Jda Programming Language — Cross-Platform Installer
# ====================================================
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/jdalang/jda-lang/main/install.sh | sh
#
# Supports:
#   - Linux x86-64      (native binary)
#   - Linux ARM64        (Docker or QEMU emulation)
#   - macOS Intel        (Docker-based compilation)
#   - macOS Apple Silicon (Docker-based compilation)
#   - FreeBSD x86-64     (native via Linux compat)
#   - WSL2               (native binary)
#
# Environment variables:
#   JDA_INSTALL_DIR      Override install directory (default: ~/.jda)
#   JDA_VERSION          Override version (default: latest release or main)
#   JDA_NO_MODIFY_PATH   Set to 1 to skip PATH modification
#
# Uninstall:
#   curl -fsSL .../install.sh | sh -s -- --uninstall

set -e

# ── Constants ────────────────────────────────────────────────────────────────

REPO="jdalang/jda-lang"
GITHUB_URL="https://github.com/$REPO"
INSTALL_DIR="${JDA_INSTALL_DIR:-$HOME/.jda}"

# ── Colors ───────────────────────────────────────────────────────────────────

if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
    R='\033[0;31m' G='\033[0;32m' Y='\033[0;33m' B='\033[0;34m'
    BD='\033[1m' RS='\033[0m'
else
    R='' G='' Y='' B='' BD='' RS=''
fi

info()  { printf "${B}info${RS}  %s\n" "$1"; }
ok()    { printf "${G}  ok${RS}  %s\n" "$1"; }
warn()  { printf "${Y}warn${RS}  %s\n" "$1"; }
err()   { printf "${R}err ${RS}  %s\n" "$1" >&2; }
die()   { err "$1"; exit 1; }

# ── Platform Detection ───────────────────────────────────────────────────────

detect_platform() {
    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m)"

    case "$OS" in
        linux)                           OS="linux" ;;
        darwin)                          OS="darwin" ;;
        freebsd)                         OS="freebsd" ;;
        mingw*|msys*|cygwin*)            OS="windows" ;;
        *) die "Unsupported OS: $OS" ;;
    esac

    case "$ARCH" in
        x86_64|amd64)  ARCH="x86_64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l)        ARCH="armv7" ;;
        *) die "Unsupported architecture: $ARCH" ;;
    esac

    # Check if running inside WSL
    IS_WSL=0
    if [ "$OS" = "linux" ] && grep -qi microsoft /proc/version 2>/dev/null; then
        IS_WSL=1
    fi
}

# ── Determine Compilation Method ─────────────────────────────────────────────

determine_method() {
    case "$OS-$ARCH" in
        linux-x86_64)
            METHOD="native"
            ;;
        linux-arm64|linux-armv7)
            if command -v docker >/dev/null 2>&1; then
                METHOD="docker"
            else
                METHOD="native"
                warn "ARM Linux — binary requires x86-64 emulation (Docker recommended)"
            fi
            ;;
        darwin-*)
            if command -v docker >/dev/null 2>&1; then
                METHOD="docker"
            else
                METHOD="macos-native"
                warn "Install Docker Desktop for full compilation support"
                warn "  https://docs.docker.com/desktop/install/mac-install/"
            fi
            ;;
        freebsd-x86_64)
            METHOD="native"
            ;;
        windows-*)
            die "Use install.ps1 for Windows. Or run this inside WSL2."
            ;;
        *)
            if command -v docker >/dev/null 2>&1; then
                METHOD="docker"
            else
                die "$OS-$ARCH requires Docker. Install: https://docs.docker.com/get-docker/"
            fi
            ;;
    esac
}

# ── Fetch Helpers ────────────────────────────────────────────────────────────

setup_fetch() {
    if command -v curl >/dev/null 2>&1; then
        FETCH="curl -fsSL"
        FETCH_OUT="curl -fsSL -o"
    elif command -v wget >/dev/null 2>&1; then
        FETCH="wget -qO-"
        FETCH_OUT="wget -qO"
    else
        die "curl or wget is required"
    fi
}

# ── Version Resolution ───────────────────────────────────────────────────────

resolve_version() {
    if [ -n "${JDA_VERSION:-}" ]; then
        VERSION="$JDA_VERSION"
        TAG="v$VERSION"
        return
    fi

    TAG=$($FETCH "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
        | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"//;s/".*//' || true)

    if [ -n "$TAG" ]; then
        VERSION="${TAG#v}"
    else
        VERSION=""
        TAG=""
    fi
}

# ── Download Release or Clone ────────────────────────────────────────────────

download_source() {
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT

    # Try release tarball first
    if [ -n "$TAG" ]; then
        RELEASE_URL="https://github.com/$REPO/releases/download/$TAG"

        case "$OS-$ARCH" in
            linux-x86_64)  TARBALL="jda-${VERSION}-linux-x86_64.tar.gz" ;;
            linux-arm64)   TARBALL="jda-${VERSION}-linux-arm64.tar.gz" ;;
            darwin-*)      TARBALL="jda-${VERSION}-macos.tar.gz" ;;
            *)             TARBALL="" ;;
        esac

        if [ -n "$TARBALL" ]; then
            info "Downloading $TARBALL..."
            if $FETCH_OUT "$TMPDIR/$TARBALL" "$RELEASE_URL/$TARBALL" 2>/dev/null; then
                # Verify checksum if available
                if $FETCH_OUT "$TMPDIR/checksums.txt" "$RELEASE_URL/checksums.txt" 2>/dev/null; then
                    EXPECTED=$(grep "$TARBALL" "$TMPDIR/checksums.txt" 2>/dev/null | awk '{print $1}' || true)
                    if [ -n "$EXPECTED" ]; then
                        if command -v sha256sum >/dev/null 2>&1; then
                            ACTUAL=$(sha256sum "$TMPDIR/$TARBALL" | awk '{print $1}')
                        elif command -v shasum >/dev/null 2>&1; then
                            ACTUAL=$(shasum -a 256 "$TMPDIR/$TARBALL" | awk '{print $1}')
                        else
                            ACTUAL=""
                        fi
                        if [ -n "$ACTUAL" ] && [ "$EXPECTED" != "$ACTUAL" ]; then
                            die "Checksum mismatch! Expected $EXPECTED, got $ACTUAL"
                        fi
                        [ -n "$ACTUAL" ] && ok "Checksum verified"
                    fi
                fi
                tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
                SRC="$TMPDIR"
                FROM_RELEASE=1
                ok "Downloaded release v$VERSION"
                return
            fi
            warn "Release tarball not found, falling back to git"
        fi
    fi

    FROM_RELEASE=0

    # Fallback: git clone
    if command -v git >/dev/null 2>&1; then
        info "Cloning repository..."
        CLONE_REF="${TAG:-main}"
        if git clone --depth 1 --branch "$CLONE_REF" "$GITHUB_URL.git" "$TMPDIR/jda" 2>/dev/null; then
            SRC="$TMPDIR/jda"
        elif git clone --depth 1 "$GITHUB_URL.git" "$TMPDIR/jda" 2>/dev/null; then
            SRC="$TMPDIR/jda"
        else
            die "Failed to clone $GITHUB_URL"
        fi
    else
        # Fallback: download tarball from main
        info "Downloading source archive..."
        $FETCH_OUT "$TMPDIR/src.tar.gz" "$GITHUB_URL/archive/refs/heads/main.tar.gz" \
            || die "Failed to download source"
        tar -xzf "$TMPDIR/src.tar.gz" -C "$TMPDIR"
        SRC=$(find "$TMPDIR" -maxdepth 1 -type d -name "jda-lang*" | head -1)
        [ -d "$SRC" ] || die "Could not find source directory after extraction"
    fi

    # Read version from source
    if [ -z "$VERSION" ] && [ -f "$SRC/VERSION" ]; then
        VERSION=$(cat "$SRC/VERSION" | tr -d '[:space:]')
    fi
    [ -z "$VERSION" ] && VERSION="dev"

    ok "Source ready (v$VERSION)"
}

# ── Install Files ────────────────────────────────────────────────────────────

install_files() {
    mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/stdlib" "$INSTALL_DIR/tools" "$INSTALL_DIR/docker"

    if [ "$FROM_RELEASE" = "1" ]; then
        # Release tarball layout: flat with jda binary, stdlib/, tools/
        [ -f "$SRC/jda" ] && cp "$SRC/jda" "$INSTALL_DIR/bin/jda1" && chmod +x "$INSTALL_DIR/bin/jda1"
        [ -d "$SRC/stdlib" ] && cp "$SRC/stdlib/"*.jda "$INSTALL_DIR/stdlib/" 2>/dev/null || true
        if [ -d "$SRC/tools" ]; then
            cp "$SRC/tools/"* "$INSTALL_DIR/tools/" 2>/dev/null || true
            chmod +x "$INSTALL_DIR/tools/"*.sh 2>/dev/null || true
            chmod +x "$INSTALL_DIR/tools/jda" 2>/dev/null || true
        fi
    else
        # Git/source layout
        if [ -f "$SRC/bootstrap/stage1/jda1" ]; then
            cp "$SRC/bootstrap/stage1/jda1" "$INSTALL_DIR/bin/jda1"
            chmod +x "$INSTALL_DIR/bin/jda1"
            ok "Compiler binary installed"
        elif [ -f "$SRC/bootstrap/stage0/jda1" ]; then
            cp "$SRC/bootstrap/stage0/jda1" "$INSTALL_DIR/bin/jda1"
            chmod +x "$INSTALL_DIR/bin/jda1"
            ok "Compiler binary installed (stage0)"
        fi

        [ -f "$SRC/bootstrap/bin/jda1-bootstrap" ] && \
            cp "$SRC/bootstrap/bin/jda1-bootstrap" "$INSTALL_DIR/bin/jda1-bootstrap" && \
            chmod +x "$INSTALL_DIR/bin/jda1-bootstrap"

        # Stdlib
        if [ -d "$SRC/stdlib" ]; then
            cp "$SRC/stdlib/"*.jda "$INSTALL_DIR/stdlib/" 2>/dev/null || true
            for subdir in "$SRC/stdlib"/*/; do
                [ -d "$subdir" ] || continue
                dname=$(basename "$subdir")
                mkdir -p "$INSTALL_DIR/stdlib/$dname"
                cp "$subdir"*.jda "$INSTALL_DIR/stdlib/$dname/" 2>/dev/null || true
            done
        fi
        PKG_COUNT=$(find "$INSTALL_DIR/stdlib" -name "*.jda" | wc -l | tr -d ' ')
        ok "Standard library ($PKG_COUNT packages)"

        # Tools
        for tool in jda jda-fmt.sh jda-doc.sh jda-lsp.sh jda-test.sh jda-pkg.sh \
                    jda-macos.sh jda-arm64.sh jda-wasm.sh jda-bench.sh jda-fuzz.sh jda-race.sh; do
            [ -f "$SRC/tools/$tool" ] && cp "$SRC/tools/$tool" "$INSTALL_DIR/tools/$tool" && \
                chmod +x "$INSTALL_DIR/tools/$tool"
        done

        # Docker
        [ -f "$SRC/docker/Dockerfile" ] && cp "$SRC/docker/Dockerfile" "$INSTALL_DIR/docker/Dockerfile"
    fi

    # Version file
    echo "$VERSION" > "$INSTALL_DIR/VERSION"

    ok "Files installed to $INSTALL_DIR"
}

# ── Create Wrapper Script ────────────────────────────────────────────────────

create_wrapper() {
    WRAPPER="$INSTALL_DIR/bin/jda"

    case "$METHOD" in
    native)
        cat > "$WRAPPER" << 'NATIVE_EOF'
#!/bin/sh
set -e
JDA_HOME="${JDA_HOME:-$HOME/.jda}"
JDA1="$JDA_HOME/bin/jda1"
[ -f "$JDA1" ] || { echo "error: jda1 not found at $JDA1" >&2; exit 1; }

# Delegate to tools/jda if it exists (full CLI)
if [ -f "$JDA_HOME/tools/jda" ]; then
    export JDA="$JDA1"
    export PATH="$JDA_HOME/bin:$PATH"
    exec "$JDA_HOME/tools/jda" "$@"
fi

# Minimal CLI fallback
case "${1:-help}" in
    build)     shift; exec "$JDA1" build "$@" ;;
    run)
        shift; TMP=$(mktemp)
        "$JDA1" build "$@" -o "$TMP" && chmod +x "$TMP" && "$TMP"; RC=$?
        rm -f "$TMP"; exit $RC ;;
    version|--version|-v)
        printf "jda %s (native)\n" "$(cat "$JDA_HOME/VERSION" 2>/dev/null || echo unknown)" ;;
    help|--help|-h|"")
        cat << 'H'
jda - The Jda Programming Language

Usage: jda <command> [options]

  build [--include <lib>] <file.jda> [-o out]   Compile
  run   [--include <lib>] <file.jda>             Compile & run
  version                                        Show version
  help                                           This message
H
        ;;
    *) exec "$JDA1" "$@" ;;
esac
NATIVE_EOF
        ;;

    docker)
        cat > "$WRAPPER" << 'DOCKER_EOF'
#!/bin/sh
set -e
JDA_HOME="${JDA_HOME:-$HOME/.jda}"
IMAGE="jda-build"
DPLAT="--platform=linux/amd64"
DULIMIT="--ulimit stack=524288000:524288000"

docker_ok() { docker info >/dev/null 2>&1; }

ensure_image() {
    docker image inspect "$IMAGE" >/dev/null 2>&1 && return
    echo "Building Jda Docker image (one-time)..."
    if [ -f "$JDA_HOME/docker/Dockerfile" ]; then
        docker build $DPLAT -t "$IMAGE" -f "$JDA_HOME/docker/Dockerfile" "$JDA_HOME"
    else
        docker build $DPLAT -t "$IMAGE" - << 'DF'
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y nasm binutils make xxd file python3 && rm -rf /var/lib/apt/lists/*
WORKDIR /jda
CMD ["/bin/bash"]
DF
    fi
}

abspath() { case "$1" in /*) echo "$1" ;; *) echo "$(pwd)/$1" ;; esac; }

docker_ok || { echo "error: Docker is not running" >&2; exit 1; }

case "${1:-help}" in
    build)
        shift; ensure_image
        INCS="" SRC="" OUT=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --include) shift; INCS="--include /w/$1"; shift ;;
                -o) shift; OUT="$1"; shift ;;
                *) SRC="$1"; shift ;;
            esac
        done
        [ -z "$SRC" ] && { echo "Usage: jda build [--include lib] <file.jda> [-o out]" >&2; exit 1; }
        DIR=$(dirname "$(abspath "$SRC")"); FN=$(basename "$SRC")
        ONAME="${OUT:-$(echo "$FN" | sed 's/\.jda$//')}"
        docker run --rm $DPLAT $DULIMIT -v "$JDA_HOME":/h -v "$DIR":/w -w /w "$IMAGE" \
            bash -c "/h/bin/jda1 build $INCS /w/$FN -o /w/$ONAME 2>&1"
        ;;
    run)
        shift; ensure_image
        INCS="" SRC=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --include) shift; INCS="--include /w/$1"; shift ;;
                *) SRC="$1"; shift ;;
            esac
        done
        [ -z "$SRC" ] && { echo "Usage: jda run [--include lib] <file.jda>" >&2; exit 1; }
        DIR=$(dirname "$(abspath "$SRC")"); FN=$(basename "$SRC")
        docker run --rm $DPLAT $DULIMIT -v "$JDA_HOME":/h -v "$DIR":/w -w /w "$IMAGE" \
            bash -c "/h/bin/jda1 build $INCS /w/$FN -o /tmp/out 2>&1 && /tmp/out"
        ;;
    version|--version|-v)
        printf "jda %s (docker)\n" "$(cat "$JDA_HOME/VERSION" 2>/dev/null || echo unknown)" ;;
    help|--help|-h|"")
        cat << 'H'
jda - The Jda Programming Language (Docker mode)

Usage: jda <command> [options]

  build [--include <lib>] <file.jda> [-o out]   Compile (via Docker)
  run   [--include <lib>] <file.jda>             Compile & run (via Docker)
  version                                        Show version
  help                                           This message

Output binaries are Linux x86-64 ELF executables.
H
        ;;
    *) echo "Unknown command: $1. Run 'jda help'." >&2; exit 1 ;;
esac
DOCKER_EOF
        ;;

    macos-native)
        cat > "$WRAPPER" << 'MACOS_EOF'
#!/bin/sh
set -e
JDA_HOME="${JDA_HOME:-$HOME/.jda}"

case "${1:-help}" in
    build)
        shift
        if [ -f "$JDA_HOME/tools/jda-macos.sh" ]; then
            exec "$JDA_HOME/tools/jda-macos.sh" "$@"
        else
            echo "error: macOS compiler not found. Install Docker for full support." >&2
            exit 1
        fi ;;
    version|--version|-v)
        printf "jda %s (macos-native)\n" "$(cat "$JDA_HOME/VERSION" 2>/dev/null || echo unknown)" ;;
    help|--help|-h|"")
        cat << 'H'
jda - The Jda Programming Language (macOS native mode)

Usage: jda <command> [options]

  build <file.jda> [-o out]   Compile (macOS native)
  version                     Show version
  help                        This message

For full features, install Docker Desktop:
  https://docs.docker.com/desktop/install/mac-install/
H
        ;;
    *) echo "Unknown command: $1. Run 'jda help'." >&2; exit 1 ;;
esac
MACOS_EOF
        ;;
    esac

    chmod +x "$WRAPPER"
    ok "Wrapper created ($METHOD mode)"
}

# ── Build Docker Image ───────────────────────────────────────────────────────

build_docker_image() {
    [ "$METHOD" = "docker" ] || return 0

    if docker image inspect jda-build >/dev/null 2>&1; then
        ok "Docker image 'jda-build' already exists"
        return 0
    fi

    info "Building Docker image 'jda-build'..."
    if [ -f "$INSTALL_DIR/docker/Dockerfile" ]; then
        docker build --platform=linux/amd64 -t jda-build \
            -f "$INSTALL_DIR/docker/Dockerfile" "$INSTALL_DIR" >/dev/null 2>&1
    else
        docker build --platform=linux/amd64 -t jda-build - >/dev/null 2>&1 << 'DEOF'
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y nasm binutils make xxd file python3 && rm -rf /var/lib/apt/lists/*
WORKDIR /jda
CMD ["/bin/bash"]
DEOF
    fi
    ok "Docker image built"
}

# ── PATH Setup ───────────────────────────────────────────────────────────────

setup_path() {
    [ "${JDA_NO_MODIFY_PATH:-0}" = "1" ] && return 0

    BIN="$INSTALL_DIR/bin"

    # Already in PATH?
    case ":${PATH}:" in
        *":${BIN}:"*) return 0 ;;
    esac

    SH=$(basename "${SHELL:-/bin/sh}")
    case "$SH" in
        zsh)  RC="$HOME/.zshrc" ;;
        bash)
            if [ -f "$HOME/.bash_profile" ]; then RC="$HOME/.bash_profile"
            elif [ -f "$HOME/.bashrc" ];     then RC="$HOME/.bashrc"
            else RC="$HOME/.profile"; fi ;;
        fish)
            RC="$HOME/.config/fish/config.fish"
            mkdir -p "$(dirname "$RC")"
            if ! grep -q "/.jda/bin" "$RC" 2>/dev/null; then
                printf '\n# Jda\nset -gx PATH %s $PATH\n' "$BIN" >> "$RC"
                ok "PATH added to $RC"
            fi
            return 0 ;;
        *) RC="$HOME/.profile" ;;
    esac

    if [ -n "$RC" ] && ! grep -q "/.jda/bin" "$RC" 2>/dev/null; then
        printf '\n# Jda Programming Language\nexport PATH="%s:$PATH"\n' "$BIN" >> "$RC"
        ok "PATH added to $RC"
    fi
}

# ── Uninstall ────────────────────────────────────────────────────────────────

do_uninstall() {
    echo ""
    info "Uninstalling Jda..."

    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
        ok "Removed $INSTALL_DIR"
    else
        warn "Nothing to remove at $INSTALL_DIR"
    fi

    for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" \
              "$HOME/.config/fish/config.fish"; do
        if [ -f "$rc" ] && grep -q "/.jda/bin" "$rc" 2>/dev/null; then
            # Use compatible sed
            if sed --version 2>/dev/null | grep -q GNU; then
                sed -i '/# Jda/d;/\/.jda\/bin/d' "$rc"
            else
                sed -i '' '/# Jda/d;/\/.jda\/bin/d' "$rc" 2>/dev/null || true
            fi
            ok "Cleaned $rc"
        fi
    done

    ok "Jda uninstalled"
    exit 0
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    printf "\n${BD}Jda Programming Language Installer${RS}\n\n"

    # Handle flags
    for arg in "$@"; do
        case "$arg" in
            --uninstall|uninstall) do_uninstall ;;
        esac
    done

    detect_platform
    determine_method
    setup_fetch
    resolve_version

    if [ "$IS_WSL" = "1" ]; then
        info "WSL detected — installing native Linux binary"
        METHOD="native"
    fi

    info "Platform: $OS/$ARCH  Method: $METHOD  Version: ${VERSION:-dev}"

    download_source
    install_files
    create_wrapper
    build_docker_image
    setup_path

    # ── Summary ──
    echo ""
    printf "${G}${BD}Jda v${VERSION} installed successfully!${RS}\n"
    echo ""
    echo "  Location:  $INSTALL_DIR"
    echo "  Method:    $METHOD"
    echo "  Stdlib:    $(find "$INSTALL_DIR/stdlib" -name '*.jda' 2>/dev/null | wc -l | tr -d ' ') packages"
    echo ""
    echo "  Quick start:"
    echo "    ${BD}jda version${RS}"
    echo "    ${BD}jda run hello.jda${RS}"
    echo "    ${BD}jda build hello.jda -o hello${RS}"
    echo ""

    case ":$PATH:" in
        *":$INSTALL_DIR/bin:"*) ;;
        *) printf "  Restart your terminal or run:\n    ${BD}export PATH=\"%s/bin:\$PATH\"${RS}\n\n" "$INSTALL_DIR" ;;
    esac
}

main "$@"
