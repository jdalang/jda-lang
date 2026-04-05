#!/bin/bash
# Build .deb package for Debian/Ubuntu
# Usage: bash installers/build-deb.sh [version]
# Produces: dist/jda_<version>_amd64.deb
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(cat "$ROOT/VERSION" | tr -d '[:space:]')}"
ARCH="amd64"
PKG="jda"
DIST="$ROOT/dist"
WORK="$DIST/deb-build"

echo "==> Building .deb package: ${PKG}_${VERSION}_${ARCH}.deb"

# Clean
rm -rf "$WORK"
mkdir -p "$WORK/DEBIAN"
mkdir -p "$WORK/usr/local/jda/bin"
mkdir -p "$WORK/usr/local/jda/stdlib"
mkdir -p "$WORK/usr/local/jda/tools"
mkdir -p "$WORK/usr/local/bin"

# Copy compiler binary
JDA_BIN="$ROOT/bootstrap/stage0/jda1"
[ -f "$JDA_BIN" ] || JDA_BIN="$ROOT/bootstrap/bin/jda1-bootstrap"
if [ -f "$JDA_BIN" ]; then
    cp "$JDA_BIN" "$WORK/usr/local/jda/bin/jda1"
    chmod 755 "$WORK/usr/local/jda/bin/jda1"
fi

# Copy stdlib
if [ -d "$ROOT/stdlib" ]; then
    cp "$ROOT/stdlib/"*.jda "$WORK/usr/local/jda/stdlib/" 2>/dev/null || true
    for subdir in "$ROOT/stdlib"/*/; do
        [ -d "$subdir" ] || continue
        dname=$(basename "$subdir")
        mkdir -p "$WORK/usr/local/jda/stdlib/$dname"
        cp "$subdir"*.jda "$WORK/usr/local/jda/stdlib/$dname/" 2>/dev/null || true
    done
fi

# Copy tools
for tool in jda jda-fmt.sh jda-doc.sh jda-lsp.sh jda-test.sh jda-pkg.sh \
            jda-macos.sh jda-arm64.sh jda-wasm.sh jda-bench.sh jda-fuzz.sh jda-race.sh; do
    [ -f "$ROOT/tools/$tool" ] && cp "$ROOT/tools/$tool" "$WORK/usr/local/jda/tools/$tool" && \
        chmod 755 "$WORK/usr/local/jda/tools/$tool"
done

# Version file
echo "$VERSION" > "$WORK/usr/local/jda/VERSION"

# Symlink jda to /usr/local/bin
cat > "$WORK/usr/local/bin/jda" << 'WRAPPER'
#!/bin/sh
export JDA_HOME="/usr/local/jda"
export JDA="/usr/local/jda/bin/jda1"
exec "/usr/local/jda/tools/jda" "$@"
WRAPPER
chmod 755 "$WORK/usr/local/bin/jda"

# Calculate installed size (in KB)
SIZE_KB=$(du -sk "$WORK" | awk '{print $1}')

# DEBIAN/control
cat > "$WORK/DEBIAN/control" << EOF
Package: $PKG
Version: $VERSION
Section: devel
Priority: optional
Architecture: $ARCH
Installed-Size: $SIZE_KB
Maintainer: Jda Language Team <hello@jdalang.org>
Homepage: https://github.com/jdalang/jda-lang
Description: Jda Programming Language
 A systems programming language bootstrapped from assembly.
 Compiles to native x86-64 machine code. Zero dependencies.
 Features: structs, traits, generics, closures, pattern matching,
 green threads, 114+ stdlib packages, self-hosted compiler.
EOF

# DEBIAN/postinst
cat > "$WORK/DEBIAN/postinst" << 'EOF'
#!/bin/sh
echo ""
echo "  Jda installed successfully!"
echo ""
echo "  Quick start:"
echo "    jda version"
echo "    jda run hello.jda"
echo "    jda build hello.jda -o hello"
echo ""
EOF
chmod 755 "$WORK/DEBIAN/postinst"

# DEBIAN/postrm
cat > "$WORK/DEBIAN/postrm" << 'EOF'
#!/bin/sh
if [ "$1" = "purge" ] || [ "$1" = "remove" ]; then
    rm -rf /usr/local/jda
fi
EOF
chmod 755 "$WORK/DEBIAN/postrm"

# Build .deb
mkdir -p "$DIST"
dpkg-deb --build "$WORK" "$DIST/${PKG}_${VERSION}_${ARCH}.deb"

# Cleanup
rm -rf "$WORK"

echo "==> Created $DIST/${PKG}_${VERSION}_${ARCH}.deb"
ls -lh "$DIST/${PKG}_${VERSION}_${ARCH}.deb"
