#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="$ROOT_DIR/bootstrap/stage1/jda1.jda"

if [[ ! -f "$TARGET" ]]; then
  echo "[workaround-check] FAIL: missing $TARGET"
  exit 1
fi

echo "[workaround-check] scanning for risky 'a * b + c' style expressions in $TARGET"

violations=0
line_no=0
while IFS= read -r line; do
  line_no=$((line_no + 1))
  code="${line%%;*}"
  if [[ "$code" == *"*"*"+"* ]]; then
    echo "[workaround-check] FAIL: line $line_no contains '*' and '+' in one statement"
    echo "  $line"
    violations=1
  fi
done < "$TARGET"

if [[ $violations -ne 0 ]]; then
  echo "[workaround-check] Split into two statements (tmp = a * b; out = tmp + c)."
  exit 1
fi

echo "[workaround-check] PASS"
