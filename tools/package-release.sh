#!/bin/bash
# Package a Jda release tarball for distribution.
# Usage: tools/package-release.sh [version]
#
# If version is omitted, reads from VERSION file.
# Produces: dist/jda-<version>-linux-x86_64.tar.gz + checksums.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION="${1:-$(cat "$ROOT/VERSION" | tr -d '[:space:]')}"
DIST_DIR="$ROOT/dist"
STAGING="$DIST_DIR/staging"
TARBALL="jda-$VERSION-linux-x86_64.tar.gz"

echo "==> Packaging Jda v$VERSION"

# --- Verify binary exists ---
JDA_BIN="$ROOT/bootstrap/bin/jda1-bootstrap"
if [ ! -f "$JDA_BIN" ]; then
    echo "error: bootstrap binary not found at $JDA_BIN" >&2
    echo "Run the build first." >&2
    exit 1
fi

# --- Stage files ---
rm -rf "$STAGING"
mkdir -p "$STAGING/stdlib"

cp "$JDA_BIN" "$STAGING/jda"
chmod +x "$STAGING/jda"

# Copy stdlib
if [ -d "$ROOT/stdlib" ]; then
    cp "$ROOT/stdlib/"*.jda "$STAGING/stdlib/" 2>/dev/null || true
fi

# Copy docs
cp "$ROOT/README.md" "$STAGING/"
cp "$ROOT/VERSION" "$STAGING/"

# --- Create tarball ---
mkdir -p "$DIST_DIR"
tar -czf "$DIST_DIR/$TARBALL" -C "$STAGING" .

# --- Checksums ---
cd "$DIST_DIR"
sha256sum "$TARBALL" > checksums.txt

# --- Cleanup ---
rm -rf "$STAGING"

echo "==> Created $DIST_DIR/$TARBALL"
echo "==> $(wc -c < "$DIST_DIR/$TARBALL") bytes"
echo "==> Checksum: $(cat checksums.txt)"
