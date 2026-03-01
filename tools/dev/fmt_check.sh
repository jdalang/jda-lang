#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

has_error=0

echo "[fmt-check] checking trailing whitespace and EOF newlines"

while IFS= read -r file; do
  case "$file" in
    *.jda|*.asm|*.md|*.sh|*.yml|*.yaml|*.txt|Dockerfile|Makefile)
      ;;
    *)
      continue
      ;;
  esac

  if rg -n "[[:blank:]]$" "$file" >/tmp/jda_fmt_trailing.$$ 2>/dev/null; then
    echo "[fmt-check] FAIL: trailing whitespace in $file"
    cat /tmp/jda_fmt_trailing.$$
    has_error=1
  fi

  if [[ -s "$file" ]]; then
    last_hex="$(tail -c1 "$file" | od -An -t x1 | tr -d ' \n')"
    if [[ "$last_hex" != "0a" ]]; then
      echo "[fmt-check] FAIL: missing trailing newline in $file"
      has_error=1
    fi
  fi
done < <(git ls-files)

rm -f /tmp/jda_fmt_trailing.$$ || true

if [[ $has_error -ne 0 ]]; then
  exit 1
fi

echo "[fmt-check] PASS"
