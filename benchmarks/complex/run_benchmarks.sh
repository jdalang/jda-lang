#!/bin/bash
# Run all complex benchmarks across all languages in Docker
# Usage: bash benchmarks/complex/run_benchmarks.sh

set -e

BENCHMARKS="sudoku raytracer regex btree lz77"

echo "============================================"
echo "  Complex Benchmarks — All Languages"
echo "============================================"
echo ""

# Compile C benchmarks
echo "--- Compiling C ---"
for b in $BENCHMARKS; do
    if [ "$b" = "raytracer" ]; then
        gcc -O2 -o /tmp/${b}_c /bench/$b/$b.c -lm 2>/dev/null
    else
        gcc -O2 -o /tmp/${b}_c /bench/$b/$b.c 2>/dev/null
    fi
    echo "  $b: OK"
done

# Compile Rust benchmarks
echo "--- Compiling Rust ---"
for b in $BENCHMARKS; do
    rustc -O -o /tmp/${b}_rs /bench/$b/$b.rs 2>/dev/null
    echo "  $b: OK"
done

# Compile Go benchmarks
echo "--- Compiling Go ---"
for b in $BENCHMARKS; do
    go build -o /tmp/${b}_go /bench/$b/$b.go 2>/dev/null
    echo "  $b: OK"
done

# Compile Jda benchmarks (if jda1 available)
JDA=""
if [ -f /bench/../bootstrap/stage0/jda1 ]; then
    JDA="/bench/../bootstrap/stage0/jda1"
fi

echo ""
echo "============================================"
echo "  Running Benchmarks"
echo "============================================"

for b in $BENCHMARKS; do
    echo ""
    echo "=== $b ==="
    echo ""

    # Sudoku needs puzzle input
    if [ "$b" = "sudoku" ]; then
        INPUT="/bench/$b/puzzles.txt"
        if [ ! -f "$INPUT" ]; then
            echo "  [SKIP] No puzzle file"
            continue
        fi
        echo "  C:"
        /tmp/${b}_c < "$INPUT"
        echo "  Rust:"
        /tmp/${b}_rs < "$INPUT"
        echo "  Go:"
        /tmp/${b}_go < "$INPUT"
        if [ -n "$JDA" ]; then
            echo "  Jda:"
            $JDA /bench/$b/$b.jda /tmp/${b}_jda 2>/dev/null && /tmp/${b}_jda < "$INPUT" || echo "    [SKIP]"
        fi
        echo "  Python:"
        python3 /bench/$b/$b.py < "$INPUT"
        echo "  Ruby:"
        ruby /bench/$b/$b.rb < "$INPUT"
    else
        echo "  C:"
        /tmp/${b}_c
        echo "  Rust:"
        /tmp/${b}_rs
        echo "  Go:"
        /tmp/${b}_go
        if [ -n "$JDA" ] && [ -f "/bench/$b/$b.jda" ]; then
            echo "  Jda:"
            $JDA /bench/$b/$b.jda /tmp/${b}_jda 2>/dev/null && /tmp/${b}_jda || echo "    [SKIP]"
        fi
        echo "  Python:"
        python3 /bench/$b/$b.py
        echo "  Ruby:"
        ruby /bench/$b/$b.rb
    fi
done
