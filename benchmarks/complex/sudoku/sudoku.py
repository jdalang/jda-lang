"""Sudoku solver — constraint propagation + backtracking (MRV). Reads puzzles from stdin."""
import sys, time

def solve(grid, row_used, col_used, box_used, possible):
    best, best_count = -1, 10
    for i in range(81):
        if grid[i] == 0:
            cnt = bin(possible[i]).count('1')
            if cnt == 0: return False
            if cnt < best_count: best, best_count = i, cnt
    if best == -1: return True

    r, c = best // 9, best % 9; b = (r // 3) * 3 + c // 3
    saved_p = possible[:]; saved_r = row_used[:]; saved_c = col_used[:]; saved_b = box_used[:]
    bits = possible[best]
    for v in range(1, 10):
        if not (bits & (1 << v)): continue
        bit = 1 << v
        grid[best] = v
        row_used[r] |= bit; col_used[c] |= bit; box_used[b] |= bit
        for i in range(81):
            if grid[i] == 0:
                ri, ci = i // 9, i % 9; bi = (ri // 3) * 3 + ci // 3
                possible[i] = 0x3FE & ~(row_used[ri] | col_used[ci] | box_used[bi])
        if solve(grid, row_used, col_used, box_used, possible): return True
        grid[best] = 0
        row_used[:] = saved_r; col_used[:] = saved_c; box_used[:] = saved_b; possible[:] = saved_p
    return False

def init_and_solve(puzzle):
    grid = [0]*81
    row_used = [0]*9; col_used = [0]*9; box_used = [0]*9
    for i in range(81):
        ch = puzzle[i]
        if '1' <= ch <= '9':
            v = int(ch); grid[i] = v; bit = 1 << v
            row_used[i//9] |= bit; col_used[i%9] |= bit
            box_used[(i//9//3)*3 + (i%9)//3] |= bit
    possible = [0]*81
    for i in range(81):
        if grid[i] == 0:
            r, c = i//9, i%9; b = (r//3)*3 + c//3
            possible[i] = 0x3FE & ~(row_used[r] | col_used[c] | box_used[b])
    return solve(grid, row_used, col_used, box_used, possible)

puzzles = [l.strip() for l in sys.stdin if len(l.strip()) == 81]
t0 = time.monotonic_ns()
solved = sum(1 for p in puzzles if init_and_solve(p))
t1 = time.monotonic_ns()
print(f"solved: {solved}/{len(puzzles)}")
print(f"time: {(t1 - t0) // 1000000} ms")
