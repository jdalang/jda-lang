#!/bin/bash
set -euo pipefail

# jda-doc — Documentation generator for Jda source files
#
# Extracts doc comments (;; comment) and generates static HTML documentation.
#
# Usage:
#   jda-doc.sh <file.jda>              Generate docs for a single file
#   jda-doc.sh <dir/>                  Generate docs for all .jda files
#   jda-doc.sh --output <dir> <src>    Write HTML to output directory
#   jda-doc.sh --json <file.jda>       Output doc data as JSON

# ─── CLI Parsing ──────────────────────────────────────────────────────────────

OUTPUT_DIR="docs"
JSON_MODE=0
MD_MODE=0
TARGETS=()

if [[ $# -eq 0 ]]; then
    echo "jda-doc — Jda documentation generator"
    echo ""
    echo "Usage:"
    echo "  jda-doc.sh <file.jda>              Generate docs to ./docs/"
    echo "  jda-doc.sh <dir/>                   Generate docs for all .jda files"
    echo "  jda-doc.sh --output <dir> <src>     Write HTML to specified directory"
    echo "  jda-doc.sh --json <file.jda>        Output doc data as JSON"
    echo "  jda-doc.sh --markdown <dir> <src>   Generate Markdown docs (GitHub)"
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --json)
            JSON_MODE=1
            shift
            ;;
        --markdown)
            MD_MODE=1
            shift
            ;;
        *)
            TARGETS+=("$1")
            shift
            ;;
    esac
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    echo "error: no files specified" >&2
    exit 1
fi

# ─── File Collection ─────────────────────────────────────────────────────────

collect_files() {
    local target="$1"
    if [[ -d "$target" ]]; then
        find "$target" -name '*.jda' -type f | sort
    elif [[ -f "$target" ]]; then
        echo "$target"
    else
        echo "error: $target not found" >&2
        exit 1
    fi
}

module_name() {
    local base
    base="$(basename "$1")"
    echo "${base%.jda}"
}

html_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    s="${s//\"/&quot;}"
    echo "$s"
}

# ─── Parse a .jda file with awk ──────────────────────────────────────────────
# Output format: tab-separated records, one per item.
# ITEM\tkind\tname\tsignature\tdoc\tline\tfile
# METHOD\tparent_name\tname\tsignature\tdoc\tline
# Fields within doc are joined with \x1F (unit separator) for line breaks.

parse_file() {
    local filepath="$1"
    awk -v filepath="$filepath" '
BEGIN {
    doc_count = 0
    in_impl = ""
    impl_brace_depth = 0
}

function flush_doc(    result, i) {
    result = ""
    for (i = 0; i < doc_count; i++) {
        if (i > 0) result = result "\x1f"
        result = result doc_buf[i]
    }
    doc_count = 0
    return result
}

function clear_doc() {
    doc_count = 0
}

{
    line = $0
    gsub(/^[ \t]+/, "", line)  # strip leading whitespace
    gsub(/[ \t]+$/, "", line)  # strip trailing whitespace

    # Doc comment
    if (line ~ /^;;/) {
        doc_text = line
        sub(/^;;[ \t]*/, "", doc_text)
        doc_buf[doc_count++] = doc_text
        next
    }

    # Blank line or regular comment — reset doc buffer
    if (line == "" || (line ~ /^;/ && line !~ /^;;/)) {
        clear_doc()
        next
    }

    # Track impl brace depth
    if (in_impl != "") {
        # Count braces in the raw line
        tmp = $0
        gsub(/[^{]/, "", tmp)
        impl_brace_depth += length(tmp)
        tmp = $0
        gsub(/[^}]/, "", tmp)
        impl_brace_depth -= length(tmp)
        if (impl_brace_depth <= 0) {
            in_impl = ""
            impl_brace_depth = 0
        }
    }

    # fn declaration
    if (line ~ /^fn[ \t]+[a-zA-Z_]/) {
        if (match(line, /^fn[ \t]+[a-zA-Z_][a-zA-Z0-9_]*/)) {
            name = line; sub(/^fn[ \t]+/, "", name); sub(/[^a-zA-Z0-9_].*/, "", name)
            sig = line
            sub(/\{.*$/, "", sig)
            gsub(/[ \t]+$/, "", sig)
            doc = flush_doc()
            if (in_impl != "") {
                printf "METHOD\t%s\t%s\t%s\t%s\t%d\n", in_impl, name, sig, doc, NR
            } else {
                printf "ITEM\tfn\t%s\t%s\t%s\t%d\t%s\n", name, sig, doc, NR, filepath
            }
        } else {
            clear_doc()
        }
        next
    }

    # struct declaration
    if (line ~ /^struct[ \t]+[a-zA-Z_]/) {
        if (match(line, /^struct[ \t]+[a-zA-Z_][a-zA-Z0-9_]*/)) {
            name = line; sub(/^struct[ \t]+/, "", name); sub(/[^a-zA-Z0-9_].*/, "", name)
            fields = ""
            if (line ~ /\{/) {
                # read fields until closing brace
                while ((getline fl) > 0) {
                    gsub(/^[ \t]+/, "", fl)
                    gsub(/[ \t]+$/, "", fl)
                    if (fl ~ /^\}/) break
                    if (fl ~ /:/ && fl !~ /^;/) {
                        sub(/,[ \t]*$/, "", fl)
                        if (fields != "") fields = fields ", "
                        fields = fields fl
                    }
                }
            }
            sig = "struct " name
            if (fields != "") sig = sig " { " fields " }"
            doc = flush_doc()
            printf "ITEM\tstruct\t%s\t%s\t%s\t%d\t%s\n", name, sig, doc, NR, filepath
        } else {
            clear_doc()
        }
        next
    }

    # enum declaration
    if (line ~ /^enum[ \t]+[a-zA-Z_]/) {
        if (match(line, /^enum[ \t]+[a-zA-Z_][a-zA-Z0-9_]*/)) {
            name = line; sub(/^enum[ \t]+/, "", name); sub(/[^a-zA-Z0-9_].*/, "", name)
            variants = ""
            if (line ~ /\{/) {
                while ((getline vl) > 0) {
                    gsub(/^[ \t]+/, "", vl)
                    gsub(/[ \t]+$/, "", vl)
                    if (vl ~ /^\}/) break
                    if (vl != "" && vl !~ /^;/) {
                        sub(/,[ \t]*$/, "", vl)
                        if (variants != "") variants = variants ", "
                        variants = variants vl
                    }
                }
            }
            sig = "enum " name
            if (variants != "") sig = sig " { " variants " }"
            doc = flush_doc()
            printf "ITEM\tenum\t%s\t%s\t%s\t%d\t%s\n", name, sig, doc, NR, filepath
        } else {
            clear_doc()
        }
        next
    }

    # const declaration
    if (line ~ /^const[ \t]+[a-zA-Z_][a-zA-Z0-9_]*[ \t]*=/) {
        if (match(line, /^const[ \t]+[a-zA-Z_][a-zA-Z0-9_]*/)) {
            name = line; sub(/^const[ \t]+/, "", name); sub(/[^a-zA-Z0-9_].*/, "", name)
            sig = line
            doc = flush_doc()
            printf "ITEM\tconst\t%s\t%s\t%s\t%d\t%s\n", name, sig, doc, NR, filepath
        } else {
            clear_doc()
        }
        next
    }

    # impl declaration
    if (line ~ /^impl[ \t]+[a-zA-Z_]/) {
        if (match(line, /^impl[ \t]+[a-zA-Z_][a-zA-Z0-9_]*/)) {
            name = line; sub(/^impl[ \t]+/, "", name); sub(/[^a-zA-Z0-9_].*/, "", name)
            sig = "impl " name
            doc = flush_doc()
            printf "ITEM\timpl\t%s\t%s\t%s\t%d\t%s\n", name, sig, doc, NR, filepath
            in_impl = name
            # count braces on this line
            tmp = $0
            gsub(/[^{]/, "", tmp)
            impl_brace_depth = length(tmp)
            tmp = $0
            gsub(/[^}]/, "", tmp)
            impl_brace_depth -= length(tmp)
        } else {
            clear_doc()
        }
        next
    }

    # Any other non-doc line resets the buffer
    clear_doc()
}
' "$filepath"
}

# ─── CSS ──────────────────────────────────────────────────────────────────────

write_css() {
    cat > "$OUTPUT_DIR/style.css" <<'CSSEOF'
:root {
  --bg: #1e1e2e;
  --fg: #cdd6f4;
  --accent: #89b4fa;
  --accent2: #a6e3a1;
  --surface: #313244;
  --overlay: #45475a;
  --subtle: #6c7086;
  --code-bg: #181825;
}
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, monospace;
  background: var(--bg); color: var(--fg);
  line-height: 1.6; padding: 2rem; max-width: 960px; margin: 0 auto;
}
h1 { color: var(--accent); margin-bottom: 1rem; font-size: 1.8rem; }
h2 { color: var(--accent2); margin: 2rem 0 0.5rem; font-size: 1.3rem;
     border-bottom: 1px solid var(--overlay); padding-bottom: 0.3rem; }
h3 { color: var(--fg); margin: 1.5rem 0 0.3rem; font-size: 1.1rem; }
a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }
.nav { margin-bottom: 2rem; }
.nav a { margin-right: 1rem; }
.item { margin: 1rem 0; padding: 1rem; background: var(--surface);
        border-radius: 6px; border-left: 3px solid var(--accent); }
.item.struct { border-left-color: var(--accent2); }
.item.enum { border-left-color: #f9e2af; }
.item.const { border-left-color: #fab387; }
.item.impl { border-left-color: #cba6f7; }
.sig { font-family: 'JetBrains Mono', 'Fira Code', monospace;
       background: var(--code-bg); padding: 0.4rem 0.8rem;
       border-radius: 4px; display: block; margin-bottom: 0.5rem;
       font-size: 0.9rem; overflow-x: auto; }
.doc { color: var(--subtle); margin-top: 0.3rem; }
.doc p { margin: 0.2rem 0; }
.source-link { font-size: 0.8rem; color: var(--subtle); float: right; }
.badge { display: inline-block; padding: 0.1rem 0.5rem; border-radius: 3px;
         font-size: 0.75rem; margin-right: 0.5rem; font-weight: bold; }
.badge.fn { background: #89b4fa33; color: var(--accent); }
.badge.struct { background: #a6e3a133; color: var(--accent2); }
.badge.enum { background: #f9e2af33; color: #f9e2af; }
.badge.const { background: #fab38733; color: #fab387; }
.badge.impl { background: #cba6f733; color: #cba6f7; }
.method { margin: 0.5rem 0 0.5rem 1.5rem; padding: 0.5rem;
          background: var(--code-bg); border-radius: 4px; }
.toc { columns: 2; column-gap: 2rem; margin: 1rem 0; }
.toc li { margin: 0.2rem 0; list-style: none; }
footer { margin-top: 3rem; padding-top: 1rem; border-top: 1px solid var(--overlay);
         color: var(--subtle); font-size: 0.85rem; }
CSSEOF
}

# ─── HTML Rendering ──────────────────────────────────────────────────────────

# render_doc_html: convert \x1F-separated doc string to <div class="doc">...</div>
render_doc_html() {
    local doc="$1"
    [[ -z "$doc" ]] && return
    local IFS=$'\x1f'
    local paragraphs=()
    local current=""
    for part in $doc; do
        if [[ -z "$part" ]]; then
            if [[ -n "$current" ]]; then
                paragraphs+=("$current")
                current=""
            fi
        else
            if [[ -n "$current" ]]; then
                current="$current $part"
            else
                current="$part"
            fi
        fi
    done
    [[ -n "$current" ]] && paragraphs+=("$current")
    echo -n '<div class="doc">'
    for p in "${paragraphs[@]}"; do
        echo -n "<p>$(html_escape "$p")</p>"
    done
    echo -n '</div>'
}

# ─── Collect all files ────────────────────────────────────────────────────────

ALL_FILES=()
for target in "${TARGETS[@]}"; do
    while IFS= read -r f; do
        ALL_FILES+=("$f")
    done < <(collect_files "$target")
done

if [[ ${#ALL_FILES[@]} -eq 0 ]]; then
    echo "error: no .jda files found" >&2
    exit 1
fi

# ─── Parse all files into a temporary data store ─────────────────────────────

# We store parsed data in a temp file, then process it.
TMPDATA="$(mktemp)"
trap 'rm -f "$TMPDATA"' EXIT

SEEN_MODULES=""
ALL_MODULE_NAMES=()

for filepath in "${ALL_FILES[@]}"; do
    mod="$(module_name "$filepath")"
    parsed="$(parse_file "$filepath")"
    if [[ -n "$parsed" ]]; then
        # Tag each line with the module name
        while IFS= read -r line; do
            echo "${mod}"$'\t'"${line}"
        done <<< "$parsed"
        case ",$SEEN_MODULES," in
            *",$mod,"*) ;;
            *)
                SEEN_MODULES="${SEEN_MODULES},${mod}"
                ALL_MODULE_NAMES+=("$mod")
                ;;
        esac
    fi
done > "$TMPDATA"

if [[ ${#ALL_MODULE_NAMES[@]} -eq 0 ]]; then
    echo "No documented items found"
    exit 0
fi

# Sort module names
IFS=$'\n' SORTED_MODULES=($(sort <<< "$(printf '%s\n' "${ALL_MODULE_NAMES[@]}")")); unset IFS

# ─── JSON Mode ────────────────────────────────────────────────────────────────

if [[ $JSON_MODE -eq 1 ]]; then
    awk -F'\t' '
BEGIN {
    first_mod = 1
    printf "{\n"
}

function json_escape(s) {
    gsub(/\\/, "\\\\", s)
    gsub(/"/, "\\\"", s)
    gsub(/\n/, "\\n", s)
    gsub(/\t/, "\\t", s)
    return s
}

function print_doc_array(doc,    n, parts, i) {
    if (doc == "") { printf "[]"; return }
    n = split(doc, parts, "\x1f")
    printf "["
    for (i = 1; i <= n; i++) {
        if (i > 1) printf ", "
        printf "\"%s\"", json_escape(parts[i])
    }
    printf "]"
}

{
    mod = $1
    rectype = $2

    if (rectype == "ITEM") {
        kind = $3; name = $4; sig = $5; doc = $6; lineno = $7; file = $8

        if (mod != cur_mod) {
            if (cur_mod != "") {
                # close methods of last impl if any
                if (in_impl_json) { printf "\n          ]"; in_impl_json = 0 }
                # close previous module
                printf "\n    }\n  ]"
            }
            if (!first_mod) printf ","
            first_mod = 0
            printf "\n  \"%s\": [\n", json_escape(mod)
            cur_mod = mod
            first_item = 1
        }

        # close methods of previous impl if any
        if (in_impl_json) { printf "\n          ]\n        }"; in_impl_json = 0; first_item = 0 }

        if (!first_item) printf ","
        first_item = 0

        printf "\n    {\n"
        printf "      \"kind\": \"%s\",\n", json_escape(kind)
        printf "      \"name\": \"%s\",\n", json_escape(name)
        printf "      \"signature\": \"%s\",\n", json_escape(sig)
        printf "      \"doc\": "; print_doc_array(doc); printf ",\n"
        printf "      \"line\": %s,\n", lineno
        printf "      \"file\": \"%s\"", json_escape(file)

        if (kind == "impl") {
            printf ",\n      \"methods\": ["
            in_impl_json = 1
            first_method = 1
        } else {
            printf ",\n      \"methods\": []"
            printf "\n    }"
        }
    }

    if (rectype == "METHOD") {
        parent = $3; mname = $4; msig = $5; mdoc = $6; mline = $7
        if (!first_method) printf ","
        first_method = 0
        printf "\n        {\n"
        printf "          \"name\": \"%s\",\n", json_escape(mname)
        printf "          \"signature\": \"%s\",\n", json_escape(msig)
        printf "          \"doc\": "; print_doc_array(mdoc); printf ",\n"
        printf "          \"line\": %s\n", mline
        printf "        }"
    }
}

END {
    if (cur_mod != "") {
        if (in_impl_json) printf "\n      ]"
        printf "\n    }\n  ]"
    }
    printf "\n}\n"
}
' "$TMPDATA"
    exit 0
fi

# ─── HTML Generation ─────────────────────────────────────────────────────────

mkdir -p "$OUTPUT_DIR"
write_css

# Generate index.html
{
    cat <<'HEADEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Jda Documentation</title>
<link rel="stylesheet" href="style.css">
</head>
<body>
<h1>Jda Documentation</h1>
<h2>Modules</h2>
<ul>
HEADEOF

    for mod in "${SORTED_MODULES[@]}"; do
        # Count fns and structs for this module
        fn_count="$(awk -F'\t' -v m="$mod" '$1==m && $2=="ITEM" && $3=="fn" {c++} END{print c+0}' "$TMPDATA")"
        struct_count="$(awk -F'\t' -v m="$mod" '$1==m && $2=="ITEM" && $3=="struct" {c++} END{print c+0}' "$TMPDATA")"
        summary=""
        [[ $fn_count -gt 0 ]] && summary="${fn_count} functions"
        if [[ $struct_count -gt 0 ]]; then
            [[ -n "$summary" ]] && summary="$summary, "
            summary="${summary}${struct_count} structs"
        fi
        [[ -n "$summary" ]] && summary=" &mdash; $summary"
        echo "<li><a href=\"${mod}.html\">$(html_escape "$mod")</a>${summary}</li>"
    done

    cat <<'FOOTEOF'
</ul>
<footer>Generated by <code>jda-doc</code></footer>
</body>
</html>
FOOTEOF
} > "$OUTPUT_DIR/index.html"

# Generate per-module HTML pages using awk
for mod in "${SORTED_MODULES[@]}"; do
    awk -F'\t' -v mod="$mod" -v sorted_mods="${SORTED_MODULES[*]}" '
BEGIN {
    # Build module nav
    n = split(sorted_mods, mods, " ")
}

function html_esc(s) {
    gsub(/&/, "\\&amp;", s)
    gsub(/</, "\\&lt;", s)
    gsub(/>/, "\\&gt;", s)
    gsub(/"/, "\\&quot;", s)
    return s
}

function render_doc(doc,    n_parts, parts, i, result, paragraphs, np, cur) {
    if (doc == "") return ""
    n_parts = split(doc, parts, "\x1f")
    np = 0
    cur = ""
    for (i = 1; i <= n_parts; i++) {
        if (parts[i] == "") {
            if (cur != "") { paragraphs[++np] = cur; cur = "" }
        } else {
            if (cur != "") cur = cur " " parts[i]
            else cur = parts[i]
        }
    }
    if (cur != "") paragraphs[++np] = cur
    result = "<div class=\"doc\">"
    for (i = 1; i <= np; i++) {
        result = result "<p>" html_esc(paragraphs[i]) "</p>"
    }
    result = result "</div>"
    return result
}

# First pass: collect items for this module
$1 == mod {
    rectype = $2
    if (rectype == "ITEM") {
        item_count++
        kind[item_count] = $3
        name[item_count] = $4
        sig[item_count] = $5
        doc[item_count] = $6
        lineno[item_count] = $7
        file[item_count] = $8
        method_count[item_count] = 0
        current_item = item_count
    }
    if (rectype == "METHOD") {
        # Find the parent impl item
        parent = $3
        for (pi = item_count; pi >= 1; pi--) {
            if (kind[pi] == "impl" && name[pi] == parent) {
                mc = ++method_count[pi]
                m_name[pi, mc] = $4
                m_sig[pi, mc] = $5
                m_doc[pi, mc] = $6
                m_line[pi, mc] = $7
                break
            }
        }
    }
}

END {
    # Header
    printf "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
    printf "<meta charset=\"utf-8\">\n"
    printf "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
    printf "<title>%s — Jda Documentation</title>\n", html_esc(mod)
    printf "<link rel=\"stylesheet\" href=\"style.css\">\n"
    printf "</head>\n<body>\n"
    printf "<h1>%s</h1>\n", html_esc(mod)

    # Nav
    printf "<div class=\"nav\"><a href=\"index.html\">Index</a>"
    for (mi = 1; mi <= n; mi++) {
        if (mods[mi] == mod) {
            printf " | <strong>%s</strong>", html_esc(mods[mi])
        } else {
            printf " | <a href=\"%s.html\">%s</a>", mods[mi], html_esc(mods[mi])
        }
    }
    printf "</div>\n"

    # TOC if more than 3 items
    if (item_count > 3) {
        printf "<ul class=\"toc\">"
        for (i = 1; i <= item_count; i++) {
            printf "<li><span class=\"badge %s\">%s</span><a href=\"#%s\">%s</a></li>", kind[i], kind[i], name[i], html_esc(name[i])
        }
        printf "</ul>\n"
    }

    # Group output by kind
    split("fn struct enum const impl", kinds, " ")
    split("Functions Structs Enums Constants Implementations", titles, " ")

    for (ki = 1; ki <= 5; ki++) {
        k = kinds[ki]
        has_kind = 0
        for (i = 1; i <= item_count; i++) {
            if (kind[i] == k) { has_kind = 1; break }
        }
        if (!has_kind) continue
        printf "<h2>%s</h2>\n", titles[ki]

        for (i = 1; i <= item_count; i++) {
            if (kind[i] != k) continue
            # basename of file
            fname = file[i]
            gsub(/.*\//, "", fname)
            printf "<div class=\"item %s\" id=\"%s\">\n", kind[i], name[i]
            printf "  <span class=\"source-link\">%s:%s</span>", html_esc(fname), lineno[i]
            printf "<span class=\"badge %s\">%s</span>", kind[i], kind[i]
            printf "<h3>%s</h3>\n", html_esc(name[i])
            printf "  <code class=\"sig\">%s</code>", html_esc(sig[i])
            printf "%s", render_doc(doc[i])

            # Methods for impl blocks
            if (method_count[i] > 0) {
                printf "<h4>Methods</h4>"
                for (mi = 1; mi <= method_count[i]; mi++) {
                    printf "<div class=\"method\">"
                    printf "<code class=\"sig\">%s</code>", html_esc(m_sig[i, mi])
                    printf "%s", render_doc(m_doc[i, mi])
                    printf "</div>"
                }
            }

            printf "\n</div>\n"
        }
    }

    printf "<footer>Generated by <code>jda-doc</code></footer>\n"
    printf "</body>\n</html>\n"
}
' "$TMPDATA" > "$OUTPUT_DIR/${mod}.html"
done

# Summary
total_items="$(awk -F'\t' '$2=="ITEM" {c++} END{print c+0}' "$TMPDATA")"
echo "Generated documentation: ${#SORTED_MODULES[@]} modules, ${total_items} items"
echo "Output: ${OUTPUT_DIR}/"
