#!/bin/bash
# Jda Language Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/jdalang/jda-lang/main/install.sh | bash
#
# Environment variables:
#   JDA_INSTALL_DIR  — installation directory (default: ~/.jda)
#   JDA_VERSION      — version to install (default: latest)

set -euo pipefail

REPO="jdalang/jda-lang"
INSTALL_DIR="${JDA_INSTALL_DIR:-$HOME/.jda}"
BIN_DIR="$INSTALL_DIR/bin"
STDLIB_DIR="$INSTALL_DIR/stdlib"

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    GREEN='' RED='' BOLD='' RESET=''
fi

info()  { echo -e "${BOLD}==> $1${RESET}"; }
ok()    { echo -e "${GREEN}==> $1${RESET}"; }
err()   { echo -e "${RED}error: $1${RESET}" >&2; exit 1; }

# --- Platform checks ---

ARCH="$(uname -m)"
OS="$(uname -s)"

if [ "$OS" != "Linux" ]; then
    err "Jda currently supports Linux only. Got: $OS"
fi

if [ "$ARCH" != "x86_64" ]; then
    err "Jda currently supports x86-64 only. Got: $ARCH"
fi

# --- Determine version ---

if [ -n "${JDA_VERSION:-}" ]; then
    VERSION="$JDA_VERSION"
    TAG="v$VERSION"
else
    info "Fetching latest version..."
    if command -v curl &>/dev/null; then
        TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | head -1 | cut -d'"' -f4)"
    elif command -v wget &>/dev/null; then
        TAG="$(wget -qO- "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name"' | head -1 | cut -d'"' -f4)"
    else
        err "curl or wget is required"
    fi

    if [ -z "$TAG" ]; then
        err "Could not determine latest version. Set JDA_VERSION=0.1.0 to install manually."
    fi
    VERSION="${TAG#v}"
fi

info "Installing Jda v$VERSION"

# --- Download ---

RELEASE_URL="https://github.com/$REPO/releases/download/$TAG"
TARBALL="jda-$VERSION-linux-x86_64.tar.gz"
DOWNLOAD_URL="$RELEASE_URL/$TARBALL"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

info "Downloading $TARBALL..."
if command -v curl &>/dev/null; then
    curl -fSL "$DOWNLOAD_URL" -o "$TMPDIR/$TARBALL"
elif command -v wget &>/dev/null; then
    wget -q "$DOWNLOAD_URL" -O "$TMPDIR/$TARBALL"
fi

# --- Verify checksum ---

CHECKSUM_URL="$RELEASE_URL/checksums.txt"
if command -v curl &>/dev/null; then
    curl -fsSL "$CHECKSUM_URL" -o "$TMPDIR/checksums.txt" 2>/dev/null || true
elif command -v wget &>/dev/null; then
    wget -q "$CHECKSUM_URL" -O "$TMPDIR/checksums.txt" 2>/dev/null || true
fi

if [ -f "$TMPDIR/checksums.txt" ] && command -v sha256sum &>/dev/null; then
    EXPECTED="$(grep "$TARBALL" "$TMPDIR/checksums.txt" | awk '{print $1}')"
    ACTUAL="$(sha256sum "$TMPDIR/$TARBALL" | awk '{print $1}')"
    if [ -n "$EXPECTED" ] && [ "$EXPECTED" != "$ACTUAL" ]; then
        err "Checksum mismatch!\n  expected: $EXPECTED\n  actual:   $ACTUAL"
    fi
    ok "Checksum verified"
fi

# --- Install ---

info "Installing to $INSTALL_DIR..."
mkdir -p "$BIN_DIR" "$STDLIB_DIR"

tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
cp "$TMPDIR/jda" "$BIN_DIR/jda"
chmod +x "$BIN_DIR/jda"

# Install stdlib if present in tarball
if [ -d "$TMPDIR/stdlib" ]; then
    cp -r "$TMPDIR/stdlib/"* "$STDLIB_DIR/"
fi

# Write version marker
echo "$VERSION" > "$INSTALL_DIR/VERSION"

# --- PATH setup ---

SHELL_NAME="$(basename "${SHELL:-/bin/bash}")"
PROFILE=""
case "$SHELL_NAME" in
    zsh)  PROFILE="$HOME/.zshrc" ;;
    bash)
        if [ -f "$HOME/.bashrc" ]; then
            PROFILE="$HOME/.bashrc"
        elif [ -f "$HOME/.bash_profile" ]; then
            PROFILE="$HOME/.bash_profile"
        fi
        ;;
    fish) PROFILE="$HOME/.config/fish/config.fish" ;;
esac

PATH_LINE="export PATH=\"$BIN_DIR:\$PATH\""

if [ -n "$PROFILE" ]; then
    if ! grep -q "$BIN_DIR" "$PROFILE" 2>/dev/null; then
        echo "" >> "$PROFILE"
        echo "# Jda Language" >> "$PROFILE"
        echo "$PATH_LINE" >> "$PROFILE"
        info "Added $BIN_DIR to PATH in $PROFILE"
    fi
fi

# --- Done ---

echo ""
ok "Jda v$VERSION installed successfully!"
echo ""
echo "  Binary:  $BIN_DIR/jda"
echo "  Stdlib:  $STDLIB_DIR/"
echo ""

if echo "$PATH" | grep -q "$BIN_DIR"; then
    echo "  Run: jda --version"
else
    echo "  To use jda, restart your shell or run:"
    echo "    $PATH_LINE"
    echo ""
    echo "  Then: jda --version"
fi
