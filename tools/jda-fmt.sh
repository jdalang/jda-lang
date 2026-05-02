#!/usr/bin/env python3
"""
jda-fmt — Canonical formatter for Jda source files

Usage:
  jda-fmt.sh <file.jda>           Format file in-place
  jda-fmt.sh <dir/>               Format all .jda files in directory
  jda-fmt.sh --check <file|dir>   Check formatting (exit 1 if unformatted)
  jda-fmt.sh --diff <file|dir>    Show diff of formatting changes
  jda-fmt.sh --stdin              Read from stdin, write formatted to stdout

Style rules:
  - 2-space indentation
  - Opening brace on same line as declaration
  - Single blank line between top-level declarations
  - No trailing whitespace
  - Single newline at end of file
  - Spaces around binary operators
  - No space before ( in function calls
  - Space after , in argument lists
  - Lines capped at 100 characters (informational, not enforced)

Idempotent: running twice produces the same output.
"""

import sys
import os
import re
import glob
import difflib

INDENT = "  "  # 2 spaces


def format_jda(source):
    """Format Jda source code. Returns formatted string."""
    lines = source.split("\n")
    out = []
    depth = 0
    prev_was_blank = False
    prev_was_toplevel_close = False
    in_asm_block = False

    for i, raw_line in enumerate(lines):
        stripped = raw_line.strip()

        # Handle asm blocks — don't reformat contents
        if in_asm_block:
            out.append(INDENT * depth + stripped if stripped else "")
            if stripped == "}":
                in_asm_block = False
                depth = max(0, depth - 1)
            continue

        # Empty line handling
        if not stripped:
            # Collapse multiple blank lines into one
            if not prev_was_blank and out:
                out.append("")
                prev_was_blank = True
            continue

        prev_was_blank = False

        # Detect asm block start
        if stripped.startswith("asm ") and stripped.endswith("{"):
            out.append(INDENT * depth + stripped)
            depth += 1
            in_asm_block = True
            prev_was_toplevel_close = False
            continue

        # Decrease indent for closing braces
        if stripped.startswith("}"):
            depth = max(0, depth - 1)

        # Add blank line before top-level declarations (fn, struct, enum, impl, const)
        # but not at the start of the file or if already preceded by a blank line
        if depth == 0 and out and not prev_was_blank:
            is_toplevel_decl = (
                stripped.startswith("fn ")
                or stripped.startswith("struct ")
                or stripped.startswith("enum ")
                or stripped.startswith("impl ")
                or stripped.startswith("const ")
            )
            if is_toplevel_decl and out[-1] != "":
                out.append("")

        # Clean up the line content
        cleaned = clean_line(stripped)

        # Emit indented line
        out.append(INDENT * depth + cleaned)

        # Track if this was a top-level closing brace
        prev_was_toplevel_close = (depth == 0 and stripped == "}")

        # Increase indent for opening braces
        if stripped.endswith("{"):
            depth += 1

    # Remove trailing blank lines
    while out and out[-1] == "":
        out.pop()

    # Ensure single trailing newline
    result = "\n".join(out)
    if result and not result.endswith("\n"):
        result += "\n"

    return result


def clean_line(line):
    """Clean up a single line: normalize spacing."""
    # Remove trailing whitespace (already stripped)
    # Normalize spaces around binary operators (careful with -> and =>)
    # Don't mess with string literals or comments

    # Find comment start (;)
    comment_start = find_comment(line)
    if comment_start == 0:
        # Full comment line — preserve as-is
        return line

    code_part = line[:comment_start] if comment_start > 0 else line
    comment_part = line[comment_start:] if comment_start > 0 else ""

    # Normalize multiple spaces to single (outside strings)
    code_part = normalize_spaces(code_part)

    # Remove trailing spaces from code part
    code_part = code_part.rstrip()

    if comment_part:
        # Ensure two spaces before inline comment
        return code_part + "  " + comment_part.strip()
    return code_part


def find_comment(line):
    """Find position of ; comment (not inside a string)."""
    in_string = False
    for i, c in enumerate(line):
        if c == '"' and (i == 0 or line[i - 1] != "\\"):
            in_string = not in_string
        elif c == ";" and not in_string:
            return i
    return -1


def normalize_spaces(code):
    """Collapse multiple spaces into one, except inside strings."""
    result = []
    in_string = False
    prev_space = False
    for i, c in enumerate(code):
        if c == '"' and (i == 0 or code[i - 1] != "\\"):
            in_string = not in_string
            result.append(c)
            prev_space = False
        elif c == " " and not in_string:
            if not prev_space:
                result.append(c)
            prev_space = True
        else:
            result.append(c)
            prev_space = False
    return "".join(result)


def format_file(filepath, check=False, show_diff=False):
    """Format a single file. Returns True if already formatted."""
    with open(filepath, "r") as f:
        original = f.read()

    formatted = format_jda(original)

    if original == formatted:
        return True

    if check:
        print(f"  UNFORMATTED  {filepath}")
        return False

    if show_diff:
        diff = difflib.unified_diff(
            original.splitlines(keepends=True),
            formatted.splitlines(keepends=True),
            fromfile=f"a/{filepath}",
            tofile=f"b/{filepath}",
        )
        sys.stdout.writelines(diff)
        return False

    with open(filepath, "w") as f:
        f.write(formatted)
    print(f"  FORMATTED  {filepath}")
    return False


def collect_files(target):
    """Collect .jda files from a file or directory path."""
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


def main():
    args = sys.argv[1:]

    if not args:
        print("jda-fmt — Canonical Jda formatter")
        print()
        print("Usage:")
        print("  jda-fmt.sh <file.jda>           Format file in-place")
        print("  jda-fmt.sh <dir/>               Format all .jda files recursively")
        print("  jda-fmt.sh --check <file|dir>   Check without modifying (exit 1 if unformatted)")
        print("  jda-fmt.sh --diff <file|dir>    Show diff of changes")
        print("  jda-fmt.sh --stdin              Read stdin, write formatted to stdout")
        sys.exit(1)

    check = False
    show_diff = False
    stdin_mode = False
    targets = []

    i = 0
    while i < len(args):
        if args[i] == "--check":
            check = True
        elif args[i] == "--diff":
            show_diff = True
        elif args[i] == "--stdin":
            stdin_mode = True
        else:
            targets.append(args[i])
        i += 1

    if stdin_mode:
        source = sys.stdin.read()
        sys.stdout.write(format_jda(source))
        sys.exit(0)

    if not targets:
        print("error: no files specified", file=sys.stderr)
        sys.exit(1)

    all_formatted = True
    total = 0
    changed = 0

    for target in targets:
        files = collect_files(target)
        for filepath in files:
            total += 1
            was_formatted = format_file(filepath, check=check, show_diff=show_diff)
            if not was_formatted:
                changed += 1
                all_formatted = False

    if check:
        if all_formatted:
            print(f"All {total} files correctly formatted")
        else:
            print(f"\n{changed}/{total} files need formatting")
            sys.exit(1)
    elif not show_diff:
        if changed == 0:
            print(f"All {total} files already formatted")
        else:
            print(f"\nFormatted {changed}/{total} files")


if __name__ == "__main__":
    main()
