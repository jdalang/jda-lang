#!/bin/bash
set -euo pipefail
#
# jda-fmt — Canonical formatter for Jda source files (pure bash + awk)
#
# Usage:
#   jda-fmt.sh <file.jda>           Format file in-place
#   jda-fmt.sh <dir/>               Format all .jda files in directory
#   jda-fmt.sh --check <file|dir>   Check formatting (exit 1 if unformatted)
#   jda-fmt.sh --diff <file|dir>    Show diff of formatting changes
#   jda-fmt.sh --stdin              Read from stdin, write formatted to stdout
#
# Style rules:
#   - 2-space indentation
#   - Opening brace on same line as declaration
#   - Single blank line between top-level declarations
#   - No trailing whitespace
#   - Single newline at end of file
#   - Collapse multiple spaces to one (outside strings)
#   - Two spaces before inline comments
#   - Preserve asm block contents (just indent)
#
# Idempotent: running twice produces the same output.

format_jda() {
  awk '
  BEGIN {
    depth = 0
    prev_was_blank = 0
    out_count = 0
  }

  function indent(d,    s, i) {
    s = ""
    for (i = 0; i < d; i++) s = s "  "
    return s
  }

  function find_comment(line,    i, n, c, in_str) {
    # Find position of ; comment not inside a string. Returns 0 if not found.
    # Returns 1-based position, or 0.
    n = length(line)
    in_str = 0
    for (i = 1; i <= n; i++) {
      c = substr(line, i, 1)
      if (c == "\"" && (i == 1 || substr(line, i-1, 1) != "\\"))
        in_str = !in_str
      else if (c == ";" && !in_str)
        return i
    }
    return 0
  }

  function normalize_spaces(code,    result, n, i, c, in_str, prev_sp) {
    # Collapse multiple spaces to one, except inside strings.
    result = ""
    n = length(code)
    in_str = 0
    prev_sp = 0
    for (i = 1; i <= n; i++) {
      c = substr(code, i, 1)
      if (c == "\"" && (i == 1 || substr(code, i-1, 1) != "\\")) {
        in_str = !in_str
        result = result c
        prev_sp = 0
      } else if (c == " " && !in_str) {
        if (!prev_sp) result = result c
        prev_sp = 1
      } else {
        result = result c
        prev_sp = 0
      }
    }
    return result
  }

  function rtrim(s) {
    sub(/[ \t]+$/, "", s)
    return s
  }

  function ltrim(s) {
    sub(/^[ \t]+/, "", s)
    return s
  }

  function trim(s) {
    return ltrim(rtrim(s))
  }

  function clean_line(line,    cpos, code_part, comment_part) {
    cpos = find_comment(line)
    if (cpos == 1) {
      # Full comment line — preserve as-is
      return line
    }
    if (cpos > 0) {
      code_part = substr(line, 1, cpos - 1)
      comment_part = substr(line, cpos)
    } else {
      code_part = line
      comment_part = ""
    }
    code_part = normalize_spaces(code_part)
    code_part = rtrim(code_part)
    if (comment_part != "") {
      comment_part = trim(comment_part)
      return code_part "  " comment_part
    }
    return code_part
  }

  function emit(line) {
    out[++out_count] = line
  }

  function starts_with(s, prefix) {
    return substr(s, 1, length(prefix)) == prefix
  }

  function ends_with(s, suffix,    sl, xl) {
    sl = length(s)
    xl = length(suffix)
    if (sl < xl) return 0
    return substr(s, sl - xl + 1) == suffix
  }

  {
    stripped = trim($0)

    # Handle asm blocks - do not reformat contents
    if (in_asm_block) {
      if (stripped == "")
        emit("")
      else
        emit(indent(depth) stripped)
      if (stripped == "}") {
        in_asm_block = 0
        depth--
        if (depth < 0) depth = 0
      }
      next
    }

    # Empty line handling
    if (stripped == "") {
      if (!prev_was_blank && out_count > 0) {
        emit("")
        prev_was_blank = 1
      }
      next
    }

    prev_was_blank = 0

    # Detect asm block start
    if (starts_with(stripped, "asm ") && ends_with(stripped, "{")) {
      emit(indent(depth) stripped)
      depth++
      in_asm_block = 1
      next
    }

    # Decrease indent for closing braces
    if (starts_with(stripped, "}")) {
      depth--
      if (depth < 0) depth = 0
    }

    # Add blank line before top-level declarations
    if (depth == 0 && out_count > 0 && !prev_was_blank) {
      if (starts_with(stripped, "fn ") || \
          starts_with(stripped, "struct ") || \
          starts_with(stripped, "enum ") || \
          starts_with(stripped, "impl ") || \
          starts_with(stripped, "const ")) {
        if (out[out_count] != "") {
          emit("")
        }
      }
    }

    # Clean up the line content
    cleaned = clean_line(stripped)

    # Emit indented line
    emit(indent(depth) cleaned)

    # Increase indent for opening braces
    if (ends_with(stripped, "{")) {
      depth++
    }
  }

  END {
    # Remove trailing blank lines
    while (out_count > 0 && out[out_count] == "")
      out_count--

    # Print all lines
    for (i = 1; i <= out_count; i++)
      print out[i]

    # awk print adds a newline after last line, giving us the trailing newline
  }
  '
}

format_file() {
  local filepath="$1"
  local check="${2:-0}"
  local show_diff="${3:-0}"

  local original formatted

  original=$(<"$filepath")
  formatted=$(printf '%s\n' "$original" | format_jda)

  # Handle empty file edge case
  if [[ -z "$original" ]]; then
    formatted=""
  fi

  if [[ "$original" == "$formatted" ]]; then
    return 0  # already formatted
  fi

  if [[ "$check" == "1" ]]; then
    echo "  UNFORMATTED  $filepath"
    return 1
  fi

  if [[ "$show_diff" == "1" ]]; then
    diff -u --label "a/$filepath" --label "b/$filepath" \
      <(printf '%s\n' "$original") <(printf '%s' "$formatted") || true
    return 1
  fi

  # Write formatted content in-place
  printf '%s' "$formatted" > "$filepath"
  echo "  FORMATTED  $filepath"
  return 1
}

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

usage() {
  echo "jda-fmt — Canonical Jda formatter"
  echo ""
  echo "Usage:"
  echo "  jda-fmt.sh <file.jda>           Format file in-place"
  echo "  jda-fmt.sh <dir/>               Format all .jda files recursively"
  echo "  jda-fmt.sh --check <file|dir>   Check without modifying (exit 1 if unformatted)"
  echo "  jda-fmt.sh --diff <file|dir>    Show diff of changes"
  echo "  jda-fmt.sh --stdin              Read stdin, write formatted to stdout"
  exit 1
}

# --- Main ---

if [[ $# -eq 0 ]]; then
  usage
fi

check=0
show_diff=0
stdin_mode=0
targets=()

for arg in "$@"; do
  case "$arg" in
    --check)   check=1 ;;
    --diff)    show_diff=1 ;;
    --stdin)   stdin_mode=1 ;;
    *)         targets+=("$arg") ;;
  esac
done

if [[ "$stdin_mode" == "1" ]]; then
  format_jda
  exit 0
fi

if [[ ${#targets[@]} -eq 0 ]]; then
  echo "error: no files specified" >&2
  exit 1
fi

all_formatted=1
total=0
changed=0

for target in "${targets[@]}"; do
  while IFS= read -r filepath; do
    total=$((total + 1))
    if ! format_file "$filepath" "$check" "$show_diff"; then
      changed=$((changed + 1))
      all_formatted=0
    fi
  done < <(collect_files "$target")
done

if [[ "$check" == "1" ]]; then
  if [[ "$all_formatted" == "1" ]]; then
    echo "All $total files correctly formatted"
  else
    echo ""
    echo "$changed/$total files need formatting"
    exit 1
  fi
elif [[ "$show_diff" == "0" ]]; then
  if [[ "$changed" == "0" ]]; then
    echo "All $total files already formatted"
  else
    echo ""
    echo "Formatted $changed/$total files"
  fi
fi
