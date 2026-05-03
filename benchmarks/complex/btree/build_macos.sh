#!/bin/bash
# Build btree_macos.jda for native macOS (x86_64 Mach-O, runs via Rosetta 2)
# Timing uses RDTSC; Rosetta 2 emulates TSC at 1 GHz so ticks/1e6 = ms
# Usage: ./build_macos.sh [output_path]
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"
OUT="${1:-$REPO/tools/btree_macos}"

docker run --rm --platform linux/amd64 --ulimit stack=524288000:524288000 \
  -v "$REPO":/jda -w /jda jda-build sh -c \
  "./bootstrap/stage0/jda1 build --macos benchmarks/complex/btree/btree_macos.jda -o /tmp/btree_macos && cp /tmp/btree_macos /jda/tools/btree_macos"

# Fix LINKEDIT filesize bug in stage0-compiled macOS binaries
python3 -c "
import struct, sys
out = sys.argv[1]
data = bytearray(open(out,'rb').read())
off = 32; ncmds = struct.unpack_from('<I', data, 16)[0]
for _ in range(ncmds):
    cmd, csz = struct.unpack_from('<II', data, off)
    if cmd == 0x19:
        name = data[off+8:off+24].decode('ascii','replace').rstrip('\x00')
        if name == '__LINKEDIT': struct.pack_into('<Q', data, off+48, 16)
    off += csz
open(out,'wb').write(data)
" "$OUT"

codesign -f -s - "$OUT"
echo "Built and signed: $OUT"
echo "Run: $OUT"
