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

# ─── remove ──────────────────────────────────────────────────────────────────

cmd_remove() {
    [ $# -ge 1 ] || die "usage: jda-pkg.sh remove <name>"
    local name="$1"

    [ -f "$MANIFEST" ] || die "no $MANIFEST found"

    # Check if dependency exists
    if ! grep -q "^${name} " "$MANIFEST" 2>/dev/null; then
        die "dependency '$name' not found in $MANIFEST"
    fi

    # Remove from manifest
    local tmp
    tmp="$(mktemp)"
    grep -v "^${name} " "$MANIFEST" > "$tmp"
    mv "$tmp" "$MANIFEST"

    # Remove cached clone
    if [ -d "$DEPS_DIR/$name" ]; then
        rm -rf "$DEPS_DIR/$name"
    fi

    # Remove from lockfile
    if [ -f "$LOCKFILE" ]; then
        tmp="$(mktemp)"
        grep -v "^${name} " "$LOCKFILE" > "$tmp" || true
        mv "$tmp" "$LOCKFILE"
    fi

    echo "Removed dependency: $name"
}

# ─── update ──────────────────────────────────────────────────────────────────

cmd_update() {
    parse_manifest

    local count=${#DEP_NAMES[@]}
    if [ "$count" -eq 0 ]; then
        echo "No dependencies to update."
        return 0
    fi

    # If a specific dep name given, only update that one
    local target="${1:-}"

    echo "Updating dependencies for $PKG_NAME v$PKG_VERSION"

    mkdir -p "$DEPS_DIR"
    : > "$LOCKFILE"

    for i in $(seq 0 $((count - 1))); do
        local name="${DEP_NAMES[$i]}"
        local url="${DEP_URLS[$i]}"
        local tag="${DEP_TAGS[$i]}"
        local dep_dir="$DEPS_DIR/$name"

        if [ -n "$target" ] && [ "$name" != "$target" ]; then
            # Re-lock unchanged dep
            if [ -d "$dep_dir" ]; then
                local commit
                commit="$(cd "$dep_dir" && git rev-parse HEAD)"
                echo "$name $tag $commit $url" >> "$LOCKFILE"
            fi
            continue
        fi

        echo "  Updating $name..."

        if [ -d "$dep_dir" ]; then
            (cd "$dep_dir" && git fetch --quiet origin 2>/dev/null) || true
        else
            git clone --quiet "$url" "$dep_dir" 2>/dev/null || \
                die "failed to clone $url"
        fi

        # Checkout latest for the tag/branch
        (cd "$dep_dir" && {
            git checkout --quiet "$tag" 2>/dev/null || \
            git checkout --quiet "origin/$tag" 2>/dev/null || \
            git checkout --quiet "tags/$tag" 2>/dev/null || true
            # If it's a branch, pull latest
            git pull --quiet origin "$tag" 2>/dev/null || true
        })

        local commit
        commit="$(cd "$dep_dir" && git rev-parse HEAD)"
        echo "$name $tag $commit $url" >> "$LOCKFILE"
        echo "  Updated $name @ $commit"
    done
}

# ─── clean ───────────────────────────────────────────────────────────────────

cmd_clean() {
    local removed=0

    if [ -d "$DEPS_DIR" ]; then
        rm -rf "$DEPS_DIR"
        echo "  Removed $DEPS_DIR/"
        removed=$((removed + 1))
    fi

    if [ -f "$LOCKFILE" ]; then
        rm -f "$LOCKFILE"
        echo "  Removed $LOCKFILE"
        removed=$((removed + 1))
    fi

    if [ -d "build" ]; then
        rm -rf "build"
        echo "  Removed build/"
        removed=$((removed + 1))
    fi

    if [ "$removed" -eq 0 ]; then
        echo "Already clean."
    else
        echo "Cleaned $removed items."
    fi
}

# ─── run (build + execute) ───────────────────────────────────────────────────

cmd_run() {
    cmd_build
    echo ""
    echo "Running $PKG_OUTPUT..."
    echo "---"
    "$PKG_OUTPUT"
}

# ─── tree (dependency tree) ──────────────────────────────────────────────────

cmd_tree() {
    parse_manifest

    echo "$PKG_NAME v$PKG_VERSION"

    local count=${#DEP_NAMES[@]}
    if [ "$count" -eq 0 ]; then
        echo "  (no dependencies)"
        return
    fi

    for i in $(seq 0 $((count - 1))); do
        local name="${DEP_NAMES[$i]}"
        local tag="${DEP_TAGS[$i]}"
        local mod="${DEP_MODS[$i]}"
        local prefix="├──"
        if [ "$i" -eq $((count - 1)) ]; then
            prefix="└──"
        fi

        local commit_info=""
        if [ -f "$LOCKFILE" ] && grep -q "^$name " "$LOCKFILE"; then
            local commit
            commit="$(grep "^$name " "$LOCKFILE" | awk '{print $3}' | head -c 8)"
            commit_info=" ($commit)"
        fi

        echo "  $prefix $name@$tag$commit_info [$mod]"

        # Check for transitive deps (if dep has its own jda.toml)
        local dep_manifest="$DEPS_DIR/$name/$MANIFEST"
        if [ -f "$dep_manifest" ]; then
            local sub_prefix="  │   "
            if [ "$i" -eq $((count - 1)) ]; then
                sub_prefix="      "
            fi
            # Simple grep for transitive deps
            local trans_deps
            trans_deps="$(grep -E "^[a-zA-Z].*=.*git" "$dep_manifest" 2>/dev/null | awk -F'=' '{print $1}' | tr -d ' ' || true)"
            if [ -n "$trans_deps" ]; then
                echo "$trans_deps" | while read -r tdep; do
                    echo "  ${sub_prefix}└── $tdep (transitive)"
                done
            fi
        fi
    done
}

# ─── check (verify manifest & lockfile) ─────────────────────────────────────

cmd_check() {
    parse_manifest
    local errors=0

    echo "Checking $PKG_NAME v$PKG_VERSION..."

    # Check entry point exists
    if [ ! -f "$PKG_ENTRY" ]; then
        echo "  ERROR: entry point '$PKG_ENTRY' not found"
        errors=$((errors + 1))
    else
        echo "  OK: entry point '$PKG_ENTRY' exists"
    fi

    # Check manifest has valid fields
    if [ -z "$PKG_NAME" ]; then
        echo "  ERROR: missing package name"
        errors=$((errors + 1))
    fi

    local count=${#DEP_NAMES[@]}

    # Check each dependency
    if [ "$count" -gt 0 ]; then
    for i in $(seq 0 $((count - 1))); do
        local name="${DEP_NAMES[$i]}"
        local mod="${DEP_MODS[$i]}"
        local dep_dir="$DEPS_DIR/$name"

        if [ ! -d "$dep_dir" ]; then
            echo "  WARN: dependency '$name' not fetched (run 'jda-pkg build')"
        else
            local mod_path="$dep_dir/$mod"
            if [ ! -f "$mod_path" ]; then
                echo "  ERROR: module '$mod' missing in dependency '$name'"
                errors=$((errors + 1))
            else
                echo "  OK: $name/$mod exists"
            fi
        fi
    done
    fi

    # Check lockfile consistency
    if [ -f "$LOCKFILE" ]; then
        local locked_count
        locked_count="$(wc -l < "$LOCKFILE" | tr -d ' ')"
        if [ "$locked_count" -ne "$count" ]; then
            echo "  WARN: lockfile has $locked_count entries, manifest has $count deps"
        else
            echo "  OK: lockfile in sync ($locked_count deps)"
        fi
    elif [ "$count" -gt 0 ]; then
        echo "  WARN: no lockfile (run 'jda-pkg build' to generate)"
    fi

    if [ "$errors" -gt 0 ]; then
        echo ""
        echo "$errors error(s) found."
        exit 1
    else
        echo ""
        echo "All checks passed."
    fi
}

# ─── install (copy stdlib package to local project) ────────────────────────

cmd_install() {
    local name="${1:-}"
    [ -n "$name" ] || die "usage: jda-pkg.sh install <package-name>"

    local stdlib_dir="$SCRIPT_DIR/../stdlib"
    local pkg_file="$stdlib_dir/${name}.jda"

    if [ ! -f "$pkg_file" ]; then
        die "unknown stdlib package: $name (see 'jda-pkg.sh search')"
    fi

    mkdir -p lib

    if [ -f "lib/${name}.jda" ]; then
        echo "Already installed: lib/${name}.jda"
    else
        cp "$pkg_file" "lib/${name}.jda"
        echo "Installed: lib/${name}.jda"
    fi

    case "$name" in
        sort|set|queue|ring|heap)
            if [ ! -f "lib/vec.jda" ]; then
                echo "  hint: '$name' depends on vec — run 'jda-pkg.sh install vec'"
            fi
            ;;
        uuid)
            if [ ! -f "lib/math.jda" ]; then
                echo "  hint: '$name' depends on math — run 'jda-pkg.sh install math'"
            fi
            if [ ! -f "lib/bitops.jda" ]; then
                echo "  hint: '$name' depends on bitops — run 'jda-pkg.sh install bitops'"
            fi
            ;;
    esac
}

# ─── list (list installed packages) ────────────────────────────────────────

cmd_list() {
    if [ ! -d "lib" ]; then
        echo "No packages installed (lib/ not found)."
        return
    fi

    local count=0
    echo "Installed packages:"
    for f in lib/*.jda; do
        if [ -f "$f" ]; then
            local name
            name="$(basename "$f" .jda)"
            printf "  %-24s %s\n" "$name" "$f"
            count=$((count + 1))
        fi
    done

    if [ "$count" -eq 0 ]; then
        echo "  (none)"
    else
        echo ""
        echo "$count package(s) installed."
    fi
}

# ─── search (search stdlib packages) ────────────────────────────────────────

cmd_search() {
    local query="${1:-}"
    local index="$SCRIPT_DIR/../stdlib/PACKAGES.md"

    if [ ! -f "$index" ]; then
        die "package index not found at $index"
    fi

    if [ -z "$query" ]; then
        echo "Available Jda stdlib packages:"
        echo ""
        # Show all packages
        grep "^|" "$index" | grep -v "^| Package" | grep -v "^|---" | while IFS='|' read -r _ name desc _; do
            name="$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            desc="$(echo "$desc" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            [ -n "$name" ] && printf "  %-24s %s\n" "$name" "$desc"
        done
    else
        echo "Search results for '$query':"
        echo ""
        grep -i "$query" "$index" | grep "^|" | while IFS='|' read -r _ name desc _; do
            name="$(echo "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            desc="$(echo "$desc" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            [ -n "$name" ] && printf "  %-24s %s\n" "$name" "$desc"
        done
    fi
}

# ─── main ─────────────────────────────────────────────────────────────────────

if [ $# -lt 1 ]; then
    echo "jda-pkg — Jda package manager"
    echo ""
    echo "Usage:"
    echo "  jda-pkg.sh init                       Create jda.toml"
    echo "  jda-pkg.sh add <name> <url> [tag]     Add git dependency"
    echo "  jda-pkg.sh remove <name>              Remove a dependency"
    echo "  jda-pkg.sh update [name]              Update deps (or one dep)"
    echo "  jda-pkg.sh build                      Resolve deps & compile"
    echo "  jda-pkg.sh run                        Build & execute"
    echo "  jda-pkg.sh deps                       List dependencies"
    echo "  jda-pkg.sh tree                       Dependency tree"
    echo "  jda-pkg.sh check                      Verify manifest & lockfile"
    echo "  jda-pkg.sh install <name>              Install stdlib package to lib/"
    echo "  jda-pkg.sh list                       List installed packages"
    echo "  jda-pkg.sh clean                      Remove build artifacts & cache"
    echo "  jda-pkg.sh search [query]             Search stdlib packages"
    exit 1
fi

CMD="$1"
shift

case "$CMD" in
    init)   cmd_init "$@" ;;
    add)    cmd_add "$@" ;;
    remove) cmd_remove "$@" ;;
    update) cmd_update "$@" ;;
    build)  cmd_build "$@" ;;
    run)    cmd_run "$@" ;;
    deps)   cmd_deps "$@" ;;
    tree)   cmd_tree "$@" ;;
    check)  cmd_check "$@" ;;
    install) cmd_install "$@" ;;
    list)   cmd_list "$@" ;;
    clean)  cmd_clean "$@" ;;
    search) cmd_search "$@" ;;
    *)      die "unknown command: $CMD" ;;
esac
