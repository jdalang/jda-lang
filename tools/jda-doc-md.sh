#!/bin/bash
set -euo pipefail

# jda-doc-md — Generate Markdown documentation from .jda source files
#
# Usage:
#   jda-doc-md.sh <dir/>                 Generate .md docs for all .jda files
#   jda-doc-md.sh --output <dir> <src>   Write markdown to output directory
#
# Extracts ;; doc comments, fn signatures, struct definitions, const values,
# trait declarations, and impl blocks. Outputs one .md file per source file
# plus an index.md.

OUTPUT_DIR="docs/stdlib-md"
TARGETS=()

if [[ $# -eq 0 ]]; then
    echo "jda-doc-md — Markdown documentation generator for Jda"
    echo ""
    echo "Usage:"
    echo "  jda-doc-md.sh <dir/>                 Generate docs for all .jda files"
    echo "  jda-doc-md.sh --output <dir> <src>   Write to specified directory"
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        *)
            TARGETS+=("$1")
            shift
            ;;
    esac
done

mkdir -p "$OUTPUT_DIR"

# Collect .jda files
FILES=()
for target in "${TARGETS[@]}"; do
    if [[ -d "$target" ]]; then
        while IFS= read -r f; do
            FILES+=("$f")
        done < <(find "$target" -name '*.jda' -type f | sort)
    elif [[ -f "$target" ]]; then
        FILES+=("$target")
    fi
done

# Track modules for index
declare -a MOD_NAMES=()
declare -a MOD_DESCS=()
declare -a MOD_FILES=()

for filepath in "${FILES[@]}"; do
    modname="$(basename "$filepath" .jda)"
    outfile="$OUTPUT_DIR/${modname}.md"

    # Extract header description (first ; line block)
    header_desc=""
    header_line=$(head -5 "$filepath" | grep "^; jda::" | head -1 | sed 's/^; jda::[^ ]* -- //' || true)
    if [[ -z "$header_line" ]]; then
        header_line=$(head -5 "$filepath" | grep "^; jda::" | head -1 | sed 's/^; jda::[^ ]* — //' || true)
    fi
    if [[ -n "$header_line" ]]; then
        header_desc="$header_line"
    fi

    MOD_NAMES+=("$modname")
    MOD_DESCS+=("$header_desc")
    MOD_FILES+=("$outfile")

    # Generate markdown with awk
    awk -v modname="$modname" -v header_desc="$header_desc" '
BEGIN {
    printf "# %s\n\n", modname
    if (header_desc != "") printf "%s\n\n", header_desc

    doc_count = 0
    fn_count = 0
    struct_count = 0
    const_count = 0
    trait_count = 0
    impl_count = 0

    # Collect everything first
    section = "header"
    header_done = 0
}

function flush_doc(    result, i) {
    result = ""
    for (i = 0; i < doc_count; i++) {
        if (i > 0) result = result "\n"
        result = result doc_buf[i]
    }
    doc_count = 0
    return result
}

# Header comment block (lines starting with ;)
/^; / && !header_done {
    next
}
/^;; / && !header_done {
    header_done = 1
}
/^$/ && !header_done {
    header_done = 1
    next
}
{ header_done = 1 }

# Doc comments
/^[ \t]*;;/ {
    line = $0
    sub(/^[ \t]*;;[ \t]?/, "", line)
    doc_buf[doc_count++] = line
    next
}

# Regular comments and blank lines reset doc
/^[ \t]*;[^;]/ || /^[ \t]*$/ {
    doc_count = 0
    next
}

# Const
/^const [A-Z]/ {
    const_count++
    const_names[const_count] = $0
    sub(/^const /, "", const_names[const_count])
    const_docs[const_count] = flush_doc()
    next
}

# Struct
/^struct / {
    struct_count++
    struct_names[struct_count] = $2
    struct_docs[struct_count] = flush_doc()
    # Collect struct body
    body = $0 "\n"
    brace = 0
    if ($0 ~ /{/) brace++
    if ($0 ~ /}/) brace--
    while (brace > 0) {
        getline
        body = body $0 "\n"
        if ($0 ~ /{/) brace++
        if ($0 ~ /}/) brace--
    }
    struct_bodies[struct_count] = body
    next
}

# Trait
/^trait / {
    trait_count++
    trait_names[trait_count] = $2
    trait_docs[trait_count] = flush_doc()
    body = $0 "\n"
    brace = 0
    if ($0 ~ /{/) brace++
    if ($0 ~ /}/) brace--
    while (brace > 0) {
        getline
        body = body $0 "\n"
        if ($0 ~ /{/) brace++
        if ($0 ~ /}/) brace--
    }
    trait_bodies[trait_count] = body
    next
}

# Impl
/^impl / {
    impl_count++
    impl_names[impl_count] = $0
    sub(/ {.*/, "", impl_names[impl_count])
    impl_docs[impl_count] = flush_doc()
    brace = 0
    if ($0 ~ /{/) brace++
    if ($0 ~ /}/) brace--
    while (brace > 0) {
        getline
        if ($0 ~ /{/) brace++
        if ($0 ~ /}/) brace--
    }
    next
}

# Function
/^fn / {
    fn_count++
    sig = $0
    sub(/ {.*/, "", sig)
    fn_sigs[fn_count] = sig
    # Extract just the name
    name = sig
    sub(/^fn /, "", name)
    sub(/[\(<].*/, "", name)
    fn_names[fn_count] = name
    fn_docs[fn_count] = flush_doc()
    # Skip function body
    brace = 0
    if ($0 ~ /{/) brace++
    if ($0 ~ /}/) brace--
    while (brace > 0) {
        getline
        if ($0 ~ /{/) brace++
        if ($0 ~ /}/) brace--
    }
    next
}

END {
    # Constants
    if (const_count > 0) {
        printf "## Constants\n\n"
        for (i = 1; i <= const_count; i++) {
            printf "```jda\n%s\n```\n", const_names[i]
            if (const_docs[i] != "") printf "\n%s\n", const_docs[i]
            printf "\n"
        }
    }

    # Structs
    if (struct_count > 0) {
        printf "## Structs\n\n"
        for (i = 1; i <= struct_count; i++) {
            printf "### `%s`\n\n", struct_names[i]
            if (struct_docs[i] != "") printf "%s\n\n", struct_docs[i]
            printf "```jda\n%s```\n\n", struct_bodies[i]
        }
    }

    # Traits
    if (trait_count > 0) {
        printf "## Traits\n\n"
        for (i = 1; i <= trait_count; i++) {
            printf "### `%s`\n\n", trait_names[i]
            if (trait_docs[i] != "") printf "%s\n\n", trait_docs[i]
            printf "```jda\n%s```\n\n", trait_bodies[i]
        }
    }

    # Functions
    if (fn_count > 0) {
        printf "## Functions\n\n"
        printf "| Function | Description |\n"
        printf "|----------|-------------|\n"
        for (i = 1; i <= fn_count; i++) {
            desc = fn_docs[i]
            gsub(/\n/, " ", desc)
            # Truncate long descriptions
            if (length(desc) > 80) desc = substr(desc, 1, 77) "..."
            printf "| `%s` | %s |\n", fn_names[i], desc
        }
        printf "\n"

        # Detailed function docs
        printf "### Details\n\n"
        for (i = 1; i <= fn_count; i++) {
            printf "#### `%s`\n\n", fn_names[i]
            printf "```jda\n%s\n```\n\n", fn_sigs[i]
            if (fn_docs[i] != "") printf "%s\n\n", fn_docs[i]
        }
    }

    printf "---\n\n*Generated by `jda-doc-md`*\n"
}
' "$filepath" > "$outfile"
done

# Generate index.md
{
    echo "# Jda Standard Library API Reference"
    echo ""
    echo "Documentation for all ${#MOD_NAMES[@]} stdlib packages."
    echo ""
    echo "| Package | Description |"
    echo "|---------|-------------|"
    for i in "${!MOD_NAMES[@]}"; do
        name="${MOD_NAMES[$i]}"
        desc="${MOD_DESCS[$i]}"
        echo "| [${name}](${name}.md) | ${desc} |"
    done
    echo ""
    echo "---"
    echo ""
    echo "*Generated by \`jda-doc-md\`*"
} > "$OUTPUT_DIR/index.md"

echo "Generated ${#MOD_NAMES[@]} markdown docs"
echo "Output: ${OUTPUT_DIR}/"
