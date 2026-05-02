#!/bin/bash
# Run sudoku benchmark for all languages — best of 3 runs
set -e
DIR="benchmarks/complex/sudoku"
PUZZLES="$DIR/puzzles.txt"

echo "=== SUDOKU BENCHMARK: 50 hard puzzles, constraint propagation + backtracking ==="
echo ""

echo "--- C (gcc -O2) ---"
gcc -O2 -o /tmp/sudoku_c $DIR/sudoku.c
for i in 1 2 3; do echo "Run $i:"; /tmp/sudoku_c < $PUZZLES; done
echo ""

echo "--- Go ---"
cd /tmp && cp /jda/$DIR/sudoku.go . && go build -o sudoku_go sudoku.go && cd /jda
for i in 1 2 3; do echo "Run $i:"; /tmp/sudoku_go < $PUZZLES; done
echo ""

echo "--- Python 3 ---"
for i in 1 2 3; do echo "Run $i:"; python3 $DIR/sudoku.py < $PUZZLES; done
echo ""

echo "--- Ruby ---"
for i in 1 2 3; do echo "Run $i:"; ruby $DIR/sudoku.rb < $PUZZLES; done
echo ""

echo "=== DONE ==="
