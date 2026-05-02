#!/bin/bash
# Package a Jda release tarball for distribution.
# Usage: tools/package-release.sh [version] [platform]
#
# Platform: x86_64 (default), arm64, macos
# Produces: dist/jda-<version>-<platform>.tar.gz + checksums.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION="${1:-$(cat "$ROOT/VERSION" | tr -d '[:space:]')}"
PLATFORM="${2:-x86_64}"
DIST_DIR="$ROOT/dist"
STAGING="$DIST_DIR/staging"

case "$PLATFORM" in
    x86_64|x86-64)
        TARBALL="jda-$VERSION-linux-x86_64.tar.gz"
        JDA_BIN="$ROOT/bootstrap/stage0/jda1"
        if [ ! -f "$JDA_BIN" ]; then
            JDA_BIN="$ROOT/bootstrap/bin/jda1-bootstrap"
        fi
        ;;
    arm64|aarch64)
        TARBALL="jda-$VERSION-linux-arm64.tar.gz"
        JDA_BIN="$ROOT/bootstrap/bin/jda1-bootstrap"
        ;;
    macos|darwin)
        TARBALL="jda-$VERSION-macos.tar.gz"
        JDA_BIN=""  # No native binary yet; include tools only
        ;;
    *)
        echo "error: unknown platform '$PLATFORM'" >&2
        echo "usage: $0 [version] [x86_64|arm64|macos]" >&2
        exit 1
        ;;
esac

echo "==> Packaging Jda v$VERSION ($PLATFORM)"

# --- Stage files ---
rm -rf "$STAGING"
mkdir -p "$STAGING/stdlib" "$STAGING/tools"

# Copy binary if available
if [ -n "$JDA_BIN" ] && [ -f "$JDA_BIN" ]; then
    cp "$JDA_BIN" "$STAGING/jda"
    chmod +x "$STAGING/jda"
fi

# Copy stdlib
if [ -d "$ROOT/stdlib" ]; then
    cp "$ROOT/stdlib/"*.jda "$STAGING/stdlib/" 2>/dev/null || true
    # Copy subdirectories
    for subdir in "$ROOT/stdlib"/*/; do
        if [ -d "$subdir" ]; then
            dirname=$(basename "$subdir")
            mkdir -p "$STAGING/stdlib/$dirname"
            cp "$subdir"*.jda "$STAGING/stdlib/$dirname/" 2>/dev/null || true
        fi
    done
fi

# Copy tools
for tool in jda-fmt.sh jda-doc.sh jda-lsp.sh jda-test.sh jda-pkg.sh jda-arm64.sh jda-macos.sh jda-wasm.sh; do
    if [ -f "$ROOT/tools/$tool" ]; then
        cp "$ROOT/tools/$tool" "$STAGING/tools/$tool"
        chmod +x "$STAGING/tools/$tool"
    fi
done

# Copy docs
[ -f "$ROOT/README.md" ] && cp "$ROOT/README.md" "$STAGING/"
[ -f "$ROOT/VERSION" ] && cp "$ROOT/VERSION" "$STAGING/"

# --- Create tarball ---
mkdir -p "$DIST_DIR"
tar -czf "$DIST_DIR/$TARBALL" -C "$STAGING" .

# --- Checksums ---
cd "$DIST_DIR"
if command -v sha256sum &>/dev/null; then
    sha256sum "$TARBALL" > checksums.txt
elif command -v shasum &>/dev/null; then
    shasum -a 256 "$TARBALL" > checksums.txt
fi

# --- Cleanup ---
rm -rf "$STAGING"

echo "==> Created $DIST_DIR/$TARBALL"
echo "==> $(wc -c < "$DIST_DIR/$TARBALL") bytes"
if [ -f "$DIST_DIR/checksums.txt" ]; then
    echo "==> Checksum: $(cat checksums.txt)"
fi
