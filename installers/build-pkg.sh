#!/bin/bash
# Build .pkg installer for macOS
# Usage: bash installers/build-pkg.sh [version]
# Produces: dist/jda-<version>-macos.pkg
# Requires: macOS with pkgbuild + productbuild
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(cat "$ROOT/VERSION" | tr -d '[:space:]')}"
DIST="$ROOT/dist"
WORK="$DIST/pkg-build"
PKG_ID="org.jdalang.jda"

echo "==> Building macOS .pkg: jda-${VERSION}-macos.pkg"

# Clean
rm -rf "$WORK"
mkdir -p "$WORK/payload/usr/local/jda/bin"
mkdir -p "$WORK/payload/usr/local/jda/stdlib"
mkdir -p "$WORK/payload/usr/local/jda/tools"
mkdir -p "$WORK/payload/usr/local/jda/docker"
mkdir -p "$WORK/payload/usr/local/bin"
mkdir -p "$WORK/scripts"

# Copy compiler binary (Linux ELF — runs via Docker on macOS)
JDA_BIN="$ROOT/bootstrap/stage0/jda1"
[ -f "$JDA_BIN" ] || JDA_BIN="$ROOT/bootstrap/bin/jda1-bootstrap"
if [ -f "$JDA_BIN" ]; then
    cp "$JDA_BIN" "$WORK/payload/usr/local/jda/bin/jda1"
    chmod 755 "$WORK/payload/usr/local/jda/bin/jda1"
fi

# Copy stdlib
if [ -d "$ROOT/stdlib" ]; then
    cp "$ROOT/stdlib/"*.jda "$WORK/payload/usr/local/jda/stdlib/" 2>/dev/null || true
    for subdir in "$ROOT/stdlib"/*/; do
        [ -d "$subdir" ] || continue
        dname=$(basename "$subdir")
        mkdir -p "$WORK/payload/usr/local/jda/stdlib/$dname"
        cp "$subdir"*.jda "$WORK/payload/usr/local/jda/stdlib/$dname/" 2>/dev/null || true
    done
fi

# Copy tools
for tool in jda jda-fmt.sh jda-doc.sh jda-lsp.sh jda-test.sh jda-pkg.sh \
            jda-macos.sh jda-arm64.sh jda-wasm.sh jda-bench.sh jda-fuzz.sh jda-race.sh; do
    [ -f "$ROOT/tools/$tool" ] && cp "$ROOT/tools/$tool" "$WORK/payload/usr/local/jda/tools/$tool" && \
        chmod 755 "$WORK/payload/usr/local/jda/tools/$tool"
done

# Copy Docker support
[ -f "$ROOT/docker/Dockerfile" ] && cp "$ROOT/docker/Dockerfile" "$WORK/payload/usr/local/jda/docker/"

# Version file
echo "$VERSION" > "$WORK/payload/usr/local/jda/VERSION"

# Create wrapper (Docker mode for macOS)
cat > "$WORK/payload/usr/local/bin/jda" << 'WRAPPER'
#!/bin/sh
set -e
JDA_HOME="/usr/local/jda"

# Check for Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "Jda on macOS requires Docker Desktop." >&2
    echo "Install: https://docs.docker.com/desktop/install/mac-install/" >&2
    echo "" >&2
    echo "After installing Docker, run: jda version" >&2
    exit 1
fi

# Delegate to tools/jda
if [ -f "$JDA_HOME/tools/jda" ]; then
    export JDA="$JDA_HOME/bin/jda1"
    export JDA_HOME
    exec "$JDA_HOME/tools/jda" "$@"
fi

echo "error: jda tools not found at $JDA_HOME/tools/jda" >&2
exit 1
WRAPPER
chmod 755 "$WORK/payload/usr/local/bin/jda"

# Post-install script
cat > "$WORK/scripts/postinstall" << 'EOF'
#!/bin/bash
echo ""
echo "=========================================="
echo "  Jda v$(cat /usr/local/jda/VERSION) installed!"
echo "=========================================="
echo ""
echo "  Jda compiles to Linux x86-64 binaries."
echo "  On macOS, compilation runs via Docker."
echo ""

# Check Docker
if command -v docker >/dev/null 2>&1; then
    echo "  ✓ Docker detected"
    # Build jda-build image
    if ! docker image inspect jda-build >/dev/null 2>&1; then
        echo "  Building jda-build Docker image (one-time)..."
        if [ -f "/usr/local/jda/docker/Dockerfile" ]; then
            docker build --platform=linux/amd64 -t jda-build \
                -f /usr/local/jda/docker/Dockerfile /usr/local/jda >/dev/null 2>&1 && \
                echo "  ✓ Docker image built" || \
                echo "  ! Docker image build failed — run 'jda version' to retry"
        fi
    else
        echo "  ✓ Docker image ready"
    fi
else
    echo "  ⚠ Docker not found"
    echo "  Install Docker Desktop:"
    echo "    https://docs.docker.com/desktop/install/mac-install/"
fi

echo ""
echo "  Quick start:"
echo "    jda version"
echo "    jda run hello.jda"
echo ""

# Add to PATH if not already there
if ! echo "$PATH" | grep -q "/usr/local/bin"; then
    echo "  Add to your shell profile:"
    echo '    export PATH="/usr/local/bin:$PATH"'
    echo ""
fi
EOF
chmod 755 "$WORK/scripts/postinstall"

# Build component package
pkgbuild \
    --root "$WORK/payload" \
    --identifier "$PKG_ID" \
    --version "$VERSION" \
    --scripts "$WORK/scripts" \
    --install-location "/" \
    "$WORK/jda-component.pkg"

# Create distribution XML for productbuild
cat > "$WORK/distribution.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Jda Programming Language</title>
    <welcome file="welcome.html"/>
    <license file="license.html"/>
    <options customize="never" require-scripts="false" hostArchitectures="x86_64,arm64"/>
    <choices-outline>
        <line choice="default">
            <line choice="$PKG_ID"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="$PKG_ID" visible="false">
        <pkg-ref id="$PKG_ID"/>
    </choice>
    <pkg-ref id="$PKG_ID" version="$VERSION" onConclusion="none">jda-component.pkg</pkg-ref>
</installer-gui-script>
EOF

# Create welcome and license HTML
mkdir -p "$WORK/resources"
cat > "$WORK/resources/welcome.html" << EOF
<html>
<body>
<h1>Jda Programming Language v$VERSION</h1>
<p>A systems programming language bootstrapped from assembly.</p>
<p>This installer will install:</p>
<ul>
<li><b>jda</b> compiler — compiles to native x86-64 machine code</li>
<li><b>stdlib</b> — 114+ standard library packages</li>
<li><b>tools</b> — formatter, doc generator, package manager, LSP</li>
</ul>
<p>Installation location: <code>/usr/local/jda</code></p>
<p><b>Note:</b> On macOS, Jda uses Docker Desktop for compilation.
<a href="https://docs.docker.com/desktop/install/mac-install/">Install Docker Desktop</a> if not already installed.</p>
</body>
</html>
EOF

cat > "$WORK/resources/license.html" << EOF
<html>
<body>
<h2>MIT License</h2>
<p>Copyright (c) 2026 Jda Language Team</p>
<p>Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:</p>
<p>The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.</p>
<p>THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.</p>
</body>
</html>
EOF

# Build final product .pkg
mkdir -p "$DIST"
productbuild \
    --distribution "$WORK/distribution.xml" \
    --resources "$WORK/resources" \
    --package-path "$WORK" \
    "$DIST/jda-${VERSION}-macos.pkg"

# Cleanup
rm -rf "$WORK"

echo "==> Created $DIST/jda-${VERSION}-macos.pkg"
ls -lh "$DIST/jda-${VERSION}-macos.pkg"
