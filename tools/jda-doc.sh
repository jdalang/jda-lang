#!/usr/bin/env python3
"""
jda-doc — Documentation generator for Jda source files

Extracts doc comments (;; comment) and generates static HTML documentation.

Usage:
  jda-doc.sh <file.jda>              Generate docs for a single file
  jda-doc.sh <dir/>                  Generate docs for all .jda files
  jda-doc.sh --output <dir> <src>    Write HTML to output directory
  jda-doc.sh --json <file.jda>       Output doc data as JSON

Doc comment format:
  ;; This is a doc comment for the next declaration.
  ;; Multiple lines are joined.
  fn my_function(x: i64) -> i64 { ... }

Generates:
  - index.html       — module index with all files
  - <module>.html    — per-module page with functions, structs, enums
  - style.css        — stylesheet
"""

import sys
import os
import re
import json
import html

# ─── Parsing ──────────────────────────────────────────────────────────────────

class DocItem:
    def __init__(self, kind, name, signature, doc, line, file):
        self.kind = kind        # "fn", "struct", "enum", "const", "impl"
        self.name = name
        self.signature = signature
        self.doc = doc          # list of doc comment lines
        self.line = line        # 1-based line number
        self.file = file
        self.methods = []       # for impl blocks

def parse_file(filepath):
    """Parse a .jda file and extract documented items."""
    with open(filepath, "r") as f:
        lines = f.readlines()

    items = []
    doc_buf = []
    current_impl = None

    for i, raw_line in enumerate(lines):
        line = raw_line.rstrip()
        stripped = line.strip()

        # Doc comment
        if stripped.startswith(";;"):
            doc_text = stripped[2:].strip()
            doc_buf.append(doc_text)
            continue

        # Regular comment or blank — reset doc buffer if not followed by decl
        if not stripped or stripped.startswith(";"):
            if not stripped.startswith(";;"):
                doc_buf = []
            continue

        # Check for declarations
        item = None

        if stripped.startswith("fn "):
            m = re.match(r"fn\s+([a-zA-Z_]\w*)\s*\(([^)]*)\)(\s*->\s*\S+)?", stripped)
            if m:
                name = m.group(1)
                sig = stripped.split("{")[0].strip()
                item = DocItem("fn", name, sig, list(doc_buf), i + 1, filepath)
                if current_impl:
                    current_impl.methods.append(item)
                else:
                    items.append(item)

        elif stripped.startswith("struct "):
            m = re.match(r"struct\s+([a-zA-Z_]\w*)", stripped)
            if m:
                name = m.group(1)
                # Collect struct fields
                fields = []
                if "{" in stripped:
                    j = i + 1
                    while j < len(lines):
                        fl = lines[j].strip()
                        if fl.startswith("}"):
                            break
                        if ":" in fl and not fl.startswith(";"):
                            fields.append(fl.rstrip(",").strip())
                        j += 1
                sig = f"struct {name}"
                if fields:
                    sig += " { " + ", ".join(fields) + " }"
                item = DocItem("struct", name, sig, list(doc_buf), i + 1, filepath)
                items.append(item)

        elif stripped.startswith("enum "):
            m = re.match(r"enum\s+([a-zA-Z_]\w*)", stripped)
            if m:
                name = m.group(1)
                variants = []
                if "{" in stripped:
                    j = i + 1
                    while j < len(lines):
                        vl = lines[j].strip()
                        if vl.startswith("}"):
                            break
                        if vl and not vl.startswith(";"):
                            variants.append(vl.rstrip(",").strip())
                        j += 1
                sig = f"enum {name}"
                if variants:
                    sig += " { " + ", ".join(variants) + " }"
                item = DocItem("enum", name, sig, list(doc_buf), i + 1, filepath)
                items.append(item)

        elif stripped.startswith("const "):
            m = re.match(r"const\s+([a-zA-Z_]\w*)\s*=\s*(.+)", stripped)
            if m:
                name = m.group(1)
                sig = stripped
                item = DocItem("const", name, sig, list(doc_buf), i + 1, filepath)
                items.append(item)

        elif stripped.startswith("impl "):
            m = re.match(r"impl\s+([a-zA-Z_]\w*)", stripped)
            if m:
                name = m.group(1)
                item = DocItem("impl", name, f"impl {name}", list(doc_buf), i + 1, filepath)
                items.append(item)
                current_impl = item

        if stripped == "}":
            current_impl = None

        # Reset doc buffer after any non-doc line
        doc_buf = []

    return items


# ─── HTML Generation ─────────────────────────────────────────────────────────

CSS = """
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
"""

def esc(s):
    return html.escape(s)

def render_doc(doc_lines):
    if not doc_lines:
        return ""
    paragraphs = []
    current = []
    for line in doc_lines:
        if not line:
            if current:
                paragraphs.append(" ".join(current))
                current = []
        else:
            current.append(line)
    if current:
        paragraphs.append(" ".join(current))
    parts = "".join(f"<p>{esc(p)}</p>" for p in paragraphs)
    return f'<div class="doc">{parts}</div>'

def render_item(item, module_name):
    badge = f'<span class="badge {item.kind}">{item.kind}</span>'
    source = f'<span class="source-link">{os.path.basename(item.file)}:{item.line}</span>'
    sig = f'<code class="sig">{esc(item.signature)}</code>'
    doc = render_doc(item.doc)

    methods_html = ""
    if item.methods:
        methods_html = "<h4>Methods</h4>"
        for m in item.methods:
            m_sig = f'<code class="sig">{esc(m.signature)}</code>'
            m_doc = render_doc(m.doc)
            methods_html += f'<div class="method">{m_sig}{m_doc}</div>'

    return f'''<div class="item {item.kind}" id="{item.name}">
  {source}{badge}<h3>{esc(item.name)}</h3>
  {sig}{doc}{methods_html}
</div>'''

def render_module_page(module_name, items, all_modules):
    nav = '<div class="nav"><a href="index.html">Index</a>'
    for m in sorted(all_modules):
        if m == module_name:
            nav += f' | <strong>{esc(m)}</strong>'
        else:
            nav += f' | <a href="{m}.html">{esc(m)}</a>'
    nav += "</div>"

    # Group by kind
    functions = [i for i in items if i.kind == "fn"]
    structs = [i for i in items if i.kind == "struct"]
    enums = [i for i in items if i.kind == "enum"]
    constants = [i for i in items if i.kind == "const"]
    impls = [i for i in items if i.kind == "impl"]

    body = f"<h1>{esc(module_name)}</h1>\n{nav}\n"

    # Table of contents
    if len(items) > 3:
        body += '<ul class="toc">'
        for item in items:
            body += f'<li><span class="badge {item.kind}">{item.kind}</span><a href="#{item.name}">{esc(item.name)}</a></li>'
        body += "</ul>"

    for title, group in [("Functions", functions), ("Structs", structs),
                          ("Enums", enums), ("Constants", constants),
                          ("Implementations", impls)]:
        if group:
            body += f"<h2>{title}</h2>\n"
            for item in group:
                body += render_item(item, module_name) + "\n"

    body += '<footer>Generated by <code>jda-doc</code></footer>'

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(module_name)} — Jda Documentation</title>
<link rel="stylesheet" href="style.css">
</head>
<body>
{body}
</body>
</html>"""

def render_index(modules):
    """Render the index page listing all modules."""
    body = "<h1>Jda Documentation</h1>\n"
    body += "<h2>Modules</h2>\n<ul>\n"
    for name, items in sorted(modules.items()):
        fn_count = sum(1 for i in items if i.kind == "fn")
        struct_count = sum(1 for i in items if i.kind == "struct")
        summary = []
        if fn_count:
            summary.append(f"{fn_count} functions")
        if struct_count:
            summary.append(f"{struct_count} structs")
        desc = f" — {', '.join(summary)}" if summary else ""
        body += f'<li><a href="{name}.html">{esc(name)}</a>{desc}</li>\n'
    body += "</ul>\n"
    body += '<footer>Generated by <code>jda-doc</code></footer>'

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Jda Documentation</title>
<link rel="stylesheet" href="style.css">
</head>
<body>
{body}
</body>
</html>"""

# ─── File collection ──────────────────────────────────────────────────────────

def collect_files(target):
    if os.path.isdir(target):
        files = []
        for root, dirs, filenames in os.walk(target):
            for fn in sorted(filenames):
                if fn.endswith(".jda"):
                    files.append(os.path.join(root, fn))
        return files
    elif os.path.isfile(target):
        return [target]
    else:
        print(f"error: {target} not found", file=sys.stderr)
        sys.exit(1)

def module_name(filepath):
    return os.path.splitext(os.path.basename(filepath))[0]

# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    args = sys.argv[1:]

    if not args:
        print("jda-doc — Jda documentation generator")
        print()
        print("Usage:")
        print("  jda-doc.sh <file.jda>              Generate docs to ./docs/")
        print("  jda-doc.sh <dir/>                   Generate docs for all .jda files")
        print("  jda-doc.sh --output <dir> <src>     Write HTML to specified directory")
        print("  jda-doc.sh --json <file.jda>        Output doc data as JSON")
        sys.exit(1)

    output_dir = "docs"
    json_mode = False
    targets = []

    i = 0
    while i < len(args):
        if args[i] == "--output" and i + 1 < len(args):
            output_dir = args[i + 1]
            i += 2
        elif args[i] == "--json":
            json_mode = True
            i += 1
        else:
            targets.append(args[i])
            i += 1

    if not targets:
        print("error: no files specified", file=sys.stderr)
        sys.exit(1)

    # Collect and parse all files
    modules = {}
    for target in targets:
        for filepath in collect_files(target):
            name = module_name(filepath)
            items = parse_file(filepath)
            if items:
                modules[name] = items

    if not modules:
        print("No documented items found")
        sys.exit(0)

    # JSON output mode
    if json_mode:
        data = {}
        for name, items in modules.items():
            data[name] = [{
                "kind": i.kind, "name": i.name, "signature": i.signature,
                "doc": i.doc, "line": i.line, "file": i.file,
                "methods": [{"name": m.name, "signature": m.signature,
                             "doc": m.doc, "line": m.line} for m in i.methods]
            } for i in items]
        print(json.dumps(data, indent=2))
        sys.exit(0)

    # Generate HTML
    os.makedirs(output_dir, exist_ok=True)

    # Write CSS
    with open(os.path.join(output_dir, "style.css"), "w") as f:
        f.write(CSS)

    # Write index
    with open(os.path.join(output_dir, "index.html"), "w") as f:
        f.write(render_index(modules))

    # Write module pages
    all_module_names = list(modules.keys())
    for name, items in modules.items():
        with open(os.path.join(output_dir, f"{name}.html"), "w") as f:
            f.write(render_module_page(name, items, all_module_names))

    total_items = sum(len(items) for items in modules.values())
    print(f"Generated documentation: {len(modules)} modules, {total_items} items")
    print(f"Output: {output_dir}/")

if __name__ == "__main__":
    main()
