#!/bin/bash
# jda-pkg — Package manager for Jda
#
# Usage:
#   jda-pkg.sh init                          # create jda.toml in current directory
#   jda-pkg.sh add <name> <git-url> [tag]    # add a dependency
#   jda-pkg.sh build                         # resolve deps, compile project
#   jda-pkg.sh deps                          # list resolved dependencies
#
# Manifest: jda.toml
# Lockfile: jda.lock
# Dependency cache: .jda-deps/
#
# Dependencies are git repos. Source files are concatenated before the project
# entry point, so dependency functions are available at compile time.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JDA="${JDA:-$SCRIPT_DIR/../bootstrap/stage0/jda1}"
MANIFEST="jda.toml"
LOCKFILE="jda.lock"
DEPS_DIR=".jda-deps"

# Compile a .jda file to a binary. Uses Docker if on macOS (jda1 is Linux ELF).
jda_compile() {
    local src="$1"
    local out="$2"
    if [ "$(uname)" = "Darwin" ]; then
        # macOS: use Docker with jda-build image
        local abs_src="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"
        local abs_out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"
        local abs_jda="$(cd "$(dirname "$JDA")" && pwd)/$(basename "$JDA")"
        local workdir="$(pwd)"
        # Mount: project dir + tmp dir + compiler dir
        docker run --rm --platform linux/amd64 \
            --ulimit stack=524288000:524288000 \
            -v "$workdir:$workdir" \
            -v "$(dirname "$abs_src"):$(dirname "$abs_src")" \
            -v "$(dirname "$abs_jda"):$(dirname "$abs_jda")" \
            -v "$(dirname "$abs_out"):$(dirname "$abs_out")" \
            -w "$workdir" \
            jda-build sh -c "$abs_jda $abs_src $abs_out >/dev/null 2>&1"
    else
        "$JDA" "$src" "$out" >/dev/null 2>&1
    fi
}

# ─── helpers ──────────────────────────────────────────────────────────────────

die() { echo "error: $*" >&2; exit 1; }

# Minimal TOML parser — reads key = "value" pairs and [section] headers
# Sets global variables: PKG_NAME, PKG_VERSION, PKG_ENTRY, PKG_OUTPUT
# Populates arrays: DEP_NAMES, DEP_URLS, DEP_TAGS, DEP_MODS
parse_manifest() {
    [ -f "$MANIFEST" ] || die "no $MANIFEST found (run 'jda-pkg.sh init' first)"

    PKG_NAME=""
    PKG_VERSION=""
    PKG_ENTRY=""
    PKG_OUTPUT=""
    DEP_NAMES=()
    DEP_URLS=()
    DEP_TAGS=()
    DEP_MODS=()

    local section=""
    while IFS= read -r line || [ -n "$line" ]; do
        # Strip comments and whitespace
        line="${line%%#*}"
        line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [ -z "$line" ] && continue

        # Section header
        if [[ "$line" =~ ^\[([a-z._]+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi

        # Key = value
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_-]*)\ *=\ *(.+)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            # Strip quotes
            val="${val#\"}"
            val="${val%\"}"
            val="${val#\'}"
            val="${val%\'}"

            case "$section" in
                package)
                    case "$key" in
                        name)    PKG_NAME="$val" ;;
                        version) PKG_VERSION="$val" ;;
                    esac
                    ;;
                build)
                    case "$key" in
                        entry)  PKG_ENTRY="$val" ;;
                        output) PKG_OUTPUT="$val" ;;
                    esac
                    ;;
                dependencies)
                    # Format: name = { git = "url", tag = "v1.0", module = "lib.jda" }
                    # Or simple: name = { git = "url" }
                    local dep_name="$key"
                    local dep_git="" dep_tag="" dep_mod=""

                    if [[ "$val" =~ git\ *=\ *\"([^\"]+)\" ]]; then
                        dep_git="${BASH_REMATCH[1]}"
                    fi
                    if [[ "$val" =~ tag\ *=\ *\"([^\"]+)\" ]]; then
                        dep_tag="${BASH_REMATCH[1]}"
                    else
                        dep_tag="main"
                    fi
                    if [[ "$val" =~ module\ *=\ *\"([^\"]+)\" ]]; then
                        dep_mod="${BASH_REMATCH[1]}"
                    else
                        dep_mod="lib.jda"
                    fi

                    [ -n "$dep_git" ] || die "dependency '$dep_name' missing 'git' field"
                    DEP_NAMES+=("$dep_name")
                    DEP_URLS+=("$dep_git")
                    DEP_TAGS+=("$dep_tag")
                    DEP_MODS+=("$dep_mod")
                    ;;
            esac
        fi
    done < "$MANIFEST"

    # Defaults
    [ -n "$PKG_NAME" ]    || PKG_NAME="$(basename "$PWD")"
    [ -n "$PKG_VERSION" ] || PKG_VERSION="0.1.0"
    [ -n "$PKG_ENTRY" ]   || PKG_ENTRY="src/main.jda"
    [ -n "$PKG_OUTPUT" ]  || PKG_OUTPUT="build/${PKG_NAME}"
}

# ─── init ─────────────────────────────────────────────────────────────────────

cmd_init() {
    if [ -f "$MANIFEST" ]; then
        die "$MANIFEST already exists"
    fi

    local name
    name="$(basename "$PWD")"

    cat > "$MANIFEST" <<EOF
[package]
name = "$name"
version = "0.1.0"

[build]
entry = "src/main.jda"
output = "build/$name"

[dependencies]
EOF

    mkdir -p src build

    # Create a hello world entry if src/main.jda doesn't exist
    if [ ! -f "src/main.jda" ]; then
        cat > "src/main.jda" <<'JDAEOF'
fn main() -> i64 {
    print "hello from jda"
    ret 0
}
JDAEOF
    fi

    echo "Initialized $MANIFEST for '$name'"
    echo "  entry: src/main.jda"
    echo "  output: build/$name"
}

# ─── add ──────────────────────────────────────────────────────────────────────

cmd_add() {
    [ $# -ge 2 ] || die "usage: jda-pkg.sh add <name> <git-url> [tag]"
    local name="$1"
    local url="$2"
    local tag="${3:-main}"

    [ -f "$MANIFEST" ] || die "no $MANIFEST found (run 'jda-pkg.sh init' first)"

    # Check if dependency already exists
    if grep -q "^${name} " "$MANIFEST" 2>/dev/null; then
        die "dependency '$name' already in $MANIFEST"
    fi

    # Append to [dependencies] section
    echo "${name} = { git = \"${url}\", tag = \"${tag}\" }" >> "$MANIFEST"
    echo "Added dependency: $name ($url @ $tag)"
}

# ─── resolve (fetch deps) ────────────────────────────────────────────────────

resolve_deps() {
    parse_manifest

    local count=${#DEP_NAMES[@]}
    if [ "$count" -eq 0 ]; then
        return 0
    fi

    mkdir -p "$DEPS_DIR"

    # Clear lockfile
    : > "$LOCKFILE"

    for i in $(seq 0 $((count - 1))); do
        local name="${DEP_NAMES[$i]}"
        local url="${DEP_URLS[$i]}"
        local tag="${DEP_TAGS[$i]}"
        local dep_dir="$DEPS_DIR/$name"

        echo "  Resolving $name ($url @ $tag)..."

        if [ -d "$dep_dir" ]; then
            # Update existing clone
            (cd "$dep_dir" && git fetch --quiet origin 2>/dev/null) || true
        else
            # Fresh clone
            git clone --quiet "$url" "$dep_dir" 2>/dev/null || \
                die "failed to clone $url"
        fi

        # Checkout the requested tag/branch
        (cd "$dep_dir" && {
            git checkout --quiet "$tag" 2>/dev/null || \
            git checkout --quiet "origin/$tag" 2>/dev/null || \
            git checkout --quiet "tags/$tag" 2>/dev/null || \
            true  # already on the right branch
        })

        # Record exact commit in lockfile
        local commit
        commit="$(cd "$dep_dir" && git rev-parse HEAD)"
        echo "$name $tag $commit $url" >> "$LOCKFILE"

        echo "  Locked $name @ $commit"
    done
}

# ─── build ────────────────────────────────────────────────────────────────────

cmd_build() {
    parse_manifest

    echo "Building $PKG_NAME v$PKG_VERSION"

    # Resolve dependencies
    local count=${#DEP_NAMES[@]}
    if [ "$count" -gt 0 ]; then
        resolve_deps
    fi

    # Check entry point exists
    [ -f "$PKG_ENTRY" ] || die "entry point '$PKG_ENTRY' not found"

    # Create output directory
    mkdir -p "$(dirname "$PKG_OUTPUT")"

    # Build combined source: deps first, then entry
    local combined
    combined="$(mktemp)"
    trap "rm -f $combined" EXIT

    for i in $(seq 0 $((count - 1))); do
        local name="${DEP_NAMES[$i]}"
        local mod="${DEP_MODS[$i]}"
        local mod_path="$DEPS_DIR/$name/$mod"

        if [ ! -f "$mod_path" ]; then
            die "module '$mod' not found in dependency '$name' ($mod_path)"
        fi

        echo "; --- dependency: $name ---" >> "$combined"
        cat "$mod_path" >> "$combined"
        echo "" >> "$combined"
    done

    # Append entry point (strip any fn main if deps have it — deps shouldn't)
    cat "$PKG_ENTRY" >> "$combined"

    # Compile
    echo "  Compiling $PKG_ENTRY -> $PKG_OUTPUT"
    if jda_compile "$combined" "$PKG_OUTPUT"; then
        chmod +x "$PKG_OUTPUT"
        echo "  Build successful: $PKG_OUTPUT"
    else
        die "compilation failed"
    fi
}

# ─── deps (list) ─────────────────────────────────────────────────────────────

cmd_deps() {
    parse_manifest

    echo "$PKG_NAME v$PKG_VERSION dependencies:"
    local count=${#DEP_NAMES[@]}
    if [ "$count" -eq 0 ]; then
        echo "  (none)"
        return
    fi
    for i in $(seq 0 $((count - 1))); do
        local name="${DEP_NAMES[$i]}"
        local url="${DEP_URLS[$i]}"
        local tag="${DEP_TAGS[$i]}"
        local status="not fetched"
        if [ -d "$DEPS_DIR/$name" ]; then
            status="fetched"
            if [ -f "$LOCKFILE" ] && grep -q "^$name " "$LOCKFILE"; then
                local commit
                commit="$(grep "^$name " "$LOCKFILE" | awk '{print $3}' | head -c 8)"
                status="locked @ $commit"
            fi
        fi
        echo "  $name ($url @ $tag) [$status]"
    done
}

# ─── main ─────────────────────────────────────────────────────────────────────

if [ $# -lt 1 ]; then
    echo "jda-pkg — Jda package manager"
    echo ""
    echo "Usage:"
    echo "  jda-pkg.sh init                       Create jda.toml"
    echo "  jda-pkg.sh add <name> <url> [tag]     Add git dependency"
    echo "  jda-pkg.sh build                      Resolve deps & compile"
    echo "  jda-pkg.sh deps                       List dependencies"
    exit 1
fi

CMD="$1"
shift

case "$CMD" in
    init)  cmd_init "$@" ;;
    add)   cmd_add "$@" ;;
    build) cmd_build "$@" ;;
    deps)  cmd_deps "$@" ;;
    *)     die "unknown command: $CMD" ;;
esac
