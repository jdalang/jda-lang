#!/bin/bash
# Build .rpm package for Fedora/RHEL/CentOS
# Usage: bash installers/build-rpm.sh [version]
# Produces: dist/jda-<version>.x86_64.rpm
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(cat "$ROOT/VERSION" | tr -d '[:space:]')}"
DIST="$ROOT/dist"
RPMBUILD="$DIST/rpmbuild"

echo "==> Building .rpm package: jda-${VERSION}.x86_64.rpm"

# Setup rpmbuild directory structure
rm -rf "$RPMBUILD"
mkdir -p "$RPMBUILD"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
mkdir -p "$RPMBUILD/BUILDROOT/jda-${VERSION}-1.x86_64"

BUILDROOT="$RPMBUILD/BUILDROOT/jda-${VERSION}-1.x86_64"
mkdir -p "$BUILDROOT/usr/local/jda/bin"
mkdir -p "$BUILDROOT/usr/local/jda/stdlib"
mkdir -p "$BUILDROOT/usr/local/jda/tools"
mkdir -p "$BUILDROOT/usr/local/bin"

# Copy files (same as .deb)
JDA_BIN="$ROOT/bootstrap/stage0/jda1"
[ -f "$JDA_BIN" ] || JDA_BIN="$ROOT/bootstrap/bin/jda1-bootstrap"
if [ -f "$JDA_BIN" ]; then
    cp "$JDA_BIN" "$BUILDROOT/usr/local/jda/bin/jda1"
    chmod 755 "$BUILDROOT/usr/local/jda/bin/jda1"
fi

if [ -d "$ROOT/stdlib" ]; then
    cp "$ROOT/stdlib/"*.jda "$BUILDROOT/usr/local/jda/stdlib/" 2>/dev/null || true
    for subdir in "$ROOT/stdlib"/*/; do
        [ -d "$subdir" ] || continue
        dname=$(basename "$subdir")
        mkdir -p "$BUILDROOT/usr/local/jda/stdlib/$dname"
        cp "$subdir"*.jda "$BUILDROOT/usr/local/jda/stdlib/$dname/" 2>/dev/null || true
    done
fi

for tool in jda jda-fmt.sh jda-doc.sh jda-lsp.sh jda-test.sh jda-pkg.sh \
            jda-macos.sh jda-arm64.sh jda-wasm.sh jda-bench.sh jda-fuzz.sh jda-race.sh; do
    [ -f "$ROOT/tools/$tool" ] && cp "$ROOT/tools/$tool" "$BUILDROOT/usr/local/jda/tools/$tool" && \
        chmod 755 "$BUILDROOT/usr/local/jda/tools/$tool"
done

echo "$VERSION" > "$BUILDROOT/usr/local/jda/VERSION"

cat > "$BUILDROOT/usr/local/bin/jda" << 'WRAPPER'
#!/bin/sh
export JDA_HOME="/usr/local/jda"
export JDA="/usr/local/jda/bin/jda1"
exec "/usr/local/jda/tools/jda" "$@"
WRAPPER
chmod 755 "$BUILDROOT/usr/local/bin/jda"

# Create .spec file
cat > "$RPMBUILD/SPECS/jda.spec" << EOF
Name:           jda
Version:        $VERSION
Release:        1
Summary:        Jda Programming Language
License:        MIT
URL:            https://github.com/jdalang/jda-lang
BuildArch:      x86_64

%description
A systems programming language bootstrapped from assembly.
Compiles to native x86-64 machine code. Zero dependencies.
Features: structs, traits, generics, closures, pattern matching,
green threads, 114+ stdlib packages, self-hosted compiler.

%files
/usr/local/jda/
/usr/local/bin/jda

%post
echo ""
echo "  Jda installed successfully!"
echo "  Run: jda version"
echo ""

%postun
rm -rf /usr/local/jda
EOF

# Build RPM
mkdir -p "$DIST"
rpmbuild --define "_topdir $RPMBUILD" \
         --buildroot "$BUILDROOT" \
         -bb "$RPMBUILD/SPECS/jda.spec"

# Copy output
cp "$RPMBUILD/RPMS/x86_64/"*.rpm "$DIST/" 2>/dev/null || true

# Cleanup
rm -rf "$RPMBUILD"

echo "==> Created RPM in $DIST/"
ls -lh "$DIST/"*.rpm 2>/dev/null || echo "RPM build may have failed"
