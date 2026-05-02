#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

has_error=0

echo "[lint] syntax-checking shell scripts"
while IFS= read -r sh_file; do
  if ! bash -n "$sh_file"; then
    echo "[lint] FAIL: bash syntax error in $sh_file"
    has_error=1
  fi
done < <(git ls-files '*.sh')

echo "[lint] checking CI/dev script executability"
while IFS= read -r sh_file; do
  if [[ ! -x "$sh_file" ]]; then
    echo "[lint] FAIL: script is not executable: $sh_file"
    has_error=1
  fi
done < <(git ls-files 'tools/ci/*.sh' 'tools/dev/*.sh')

echo "[lint] checking generated docs presence"
if [[ ! -f docs/CONFORMANCE_STATUS.md ]]; then
  echo "[lint] FAIL: missing generated docs file docs/CONFORMANCE_STATUS.md"
  has_error=1
fi

echo "[lint] checking conformance fixture directories"
for dir in tests/conformance/stage0/pass tests/conformance/stage0/fail tests/conformance/stage1/pass tests/conformance/stage1/fail; do
  if [[ ! -d "$dir" ]]; then
    echo "[lint] FAIL: missing directory $dir"
    has_error=1
  fi
done

if [[ $has_error -ne 0 ]]; then
  exit 1
fi

echo "[lint] PASS"
