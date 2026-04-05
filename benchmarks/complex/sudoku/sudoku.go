package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
	"time"
)

var grid [81]int
var possible [81]int
var rowUsed, colUsed, boxUsed [9]int

func initBoard(puzzle string) {
	rowUsed = [9]int{}; colUsed = [9]int{}; boxUsed = [9]int{}
	for i := 0; i < 81; i++ {
		if puzzle[i] >= '1' && puzzle[i] <= '9' {
			v := int(puzzle[i] - '0'); grid[i] = v; bit := 1 << v
			rowUsed[i/9] |= bit; colUsed[i%9] |= bit; boxUsed[(i/9/3)*3+(i%9)/3] |= bit
		} else {
			grid[i] = 0
		}
	}
	for i := 0; i < 81; i++ {
		if grid[i] == 0 {
			r, c := i/9, i%9; b := (r/3)*3 + c/3
			possible[i] = 0x3FE & ^(rowUsed[r] | colUsed[c] | boxUsed[b])
		} else {
			possible[i] = 0
		}
	}
}

func countBits(x int) int {
	c := 0; for x != 0 { c += x & 1; x >>= 1 }; return c
}

func solve() bool {
	best, bestCount := -1, 10
	for i := 0; i < 81; i++ {
		if grid[i] == 0 {
			cnt := countBits(possible[i])
			if cnt == 0 { return false }
			if cnt < bestCount { best = i; bestCount = cnt }
		}
	}
	if best == -1 { return true }
	r, c := best/9, best%9; b := (r/3)*3 + c/3
	savedP := possible; savedR := rowUsed; savedC := colUsed; savedB := boxUsed
	bits := possible[best]
	for v := 1; v <= 9; v++ {
		if bits&(1<<v) == 0 { continue }
		bit := 1 << v
		grid[best] = v
		rowUsed[r] |= bit; colUsed[c] |= bit; boxUsed[b] |= bit
		for i := 0; i < 81; i++ {
			if grid[i] == 0 {
				ri, ci := i/9, i%9; bi := (ri/3)*3 + ci/3
				possible[i] = 0x3FE & ^(rowUsed[ri] | colUsed[ci] | boxUsed[bi])
			}
		}
		if solve() { return true }
		grid[best] = 0
		possible = savedP; rowUsed = savedR; colUsed = savedC; boxUsed = savedB
	}
	return false
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	var puzzles []string
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if len(line) == 81 { puzzles = append(puzzles, line) }
	}
	t0 := time.Now()
	solved := 0
	for _, p := range puzzles {
		initBoard(p)
		if solve() { solved++ }
	}
	ms := time.Since(t0).Milliseconds()
	fmt.Printf("solved: %d/%d\n", solved, len(puzzles))
	fmt.Printf("time: %d ms\n", ms)
}
