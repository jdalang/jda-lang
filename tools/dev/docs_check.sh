#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

bash tools/dev/generate_docs.sh >/dev/null

if ! git diff --quiet -- docs/CONFORMANCE_STATUS.md; then
  echo "[docs-check] FAIL: docs/CONFORMANCE_STATUS.md is stale"
  echo "[docs-check] run: make docs"
  git --no-pager diff -- docs/CONFORMANCE_STATUS.md
  exit 1
fi

echo "[docs-check] PASS"
