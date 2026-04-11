#!/bin/bash
# Run all complex benchmarks across 6 languages in Docker
# Usage: docker run ... bash benchmarks/complex/run_benchmarks.sh
# Or:    bash benchmarks/complex/run_benchmarks.sh  (from inside Docker)

set -e

BENCH_DIR="benchmarks/complex"
JDA="./bootstrap/stage0/jda1"
BENCHMARKS="sudoku btree lz77 regex raytracer"

echo "============================================"
echo "  Complex Benchmarks — 6 Languages"
echo "============================================"
echo ""

# --- Compile all languages ---
echo "--- Compiling C (gcc -O2) ---"
for b in $BENCHMARKS; do
    src="$BENCH_DIR/$b/$b.c"
    [ ! -f "$src" ] && continue
    if [ "$b" = "raytracer" ]; then
        gcc -O2 -o /tmp/${b}_c "$src" -lm 2>/dev/null
    else
        gcc -O2 -o /tmp/${b}_c "$src" 2>/dev/null
    fi
    echo "  $b: OK"
done

echo "--- Compiling Rust (rustc -O) ---"
for b in $BENCHMARKS; do
    src="$BENCH_DIR/$b/$b.rs"
    [ ! -f "$src" ] && continue
    rustc -O -o /tmp/${b}_rs "$src" 2>/dev/null
    echo "  $b: OK"
done

echo "--- Compiling Go ---"
for b in $BENCHMARKS; do
    src="$BENCH_DIR/$b/$b.go"
    [ ! -f "$src" ] && continue
    go build -o /tmp/${b}_go "$src" 2>/dev/null
    echo "  $b: OK"
done

echo "--- Compiling Jda ---"
for b in $BENCHMARKS; do
    src="$BENCH_DIR/$b/$b.jda"
    [ ! -f "$src" ] && continue
    if $JDA "$src" /tmp/${b}_jda 2>/dev/null; then
        echo "  $b: OK"
    else
        echo "  $b: FAILED"
    fi
done

echo ""
echo "============================================"
echo "  Running Benchmarks"
echo "============================================"

run_bench() {
    local name=$1
    local bin=$2
    local input=$3

    if [ ! -f "$bin" ]; then
        echo "    [SKIP] not compiled"
        return
    fi
    if [ -n "$input" ]; then
        "$bin" < "$input"
    else
        "$bin"
    fi
}

for b in $BENCHMARKS; do
    echo ""
    echo "=== $b ==="

    INPUT=""
    if [ "$b" = "sudoku" ]; then
        INPUT="$BENCH_DIR/$b/puzzles.txt"
        if [ ! -f "$INPUT" ]; then
            echo "  [SKIP] No puzzle file"
            continue
        fi
    fi

    for lang in C Rust Go Jda Python Ruby; do
        echo "  $lang:"
        case $lang in
            C)      run_bench "$b" "/tmp/${b}_c" "$INPUT" ;;
            Rust)   run_bench "$b" "/tmp/${b}_rs" "$INPUT" ;;
            Go)     run_bench "$b" "/tmp/${b}_go" "$INPUT" ;;
            Jda)    run_bench "$b" "/tmp/${b}_jda" "$INPUT" ;;
            Python)
                src="$BENCH_DIR/$b/$b.py"
                if [ -f "$src" ]; then
                    if [ -n "$INPUT" ]; then
                        python3 "$src" < "$INPUT"
                    else
                        python3 "$src"
                    fi
                else
                    echo "    [SKIP]"
                fi
                ;;
            Ruby)
                src="$BENCH_DIR/$b/$b.rb"
                if [ -f "$src" ]; then
                    if [ -n "$INPUT" ]; then
                        ruby "$src" < "$INPUT"
                    else
                        ruby "$src"
                    fi
                else
                    echo "    [SKIP]"
                fi
                ;;
        esac
    done
done

echo ""
echo "============================================"
echo "  Done"
echo "============================================"
