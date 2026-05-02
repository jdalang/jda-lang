# Sudoku solver — constraint propagation + backtracking (MRV). Reads puzzles from stdin.

def count_bits(x)
  c = 0; while x != 0; c += x & 1; x >>= 1; end; c
end

def solve(grid, row_used, col_used, box_used, possible)
  best, best_count = -1, 10
  81.times do |i|
    if grid[i] == 0
      cnt = count_bits(possible[i])
      return false if cnt == 0
      if cnt < best_count; best = i; best_count = cnt; end
    end
  end
  return true if best == -1

  r, c = best / 9, best % 9; b = (r / 3) * 3 + c / 3
  saved_p = possible.dup; saved_r = row_used.dup; saved_c = col_used.dup; saved_b = box_used.dup

  (1..9).each do |v|
    next if possible[best] & (1 << v) == 0
    bit = 1 << v
    grid[best] = v
    row_used[r] |= bit; col_used[c] |= bit; box_used[b] |= bit
    81.times do |i|
      if grid[i] == 0
        ri, ci = i / 9, i % 9; bi = (ri / 3) * 3 + ci / 3
        possible[i] = 0x3FE & ~(row_used[ri] | col_used[ci] | box_used[bi])
      end
    end
    return true if solve(grid, row_used, col_used, box_used, possible)
    grid[best] = 0
    81.times { |i| row_used[i%9] = saved_r[i%9] if i < 9; col_used[i%9] = saved_c[i%9] if i < 9; box_used[i%9] = saved_b[i%9] if i < 9; possible[i] = saved_p[i] }
  end
  false
end

def init_and_solve(puzzle)
  grid = Array.new(81, 0)
  row_used = Array.new(9, 0); col_used = Array.new(9, 0); box_used = Array.new(9, 0)
  81.times do |i|
    ch = puzzle[i]
    if ch >= '1' && ch <= '9'
      v = ch.to_i; grid[i] = v; bit = 1 << v
      row_used[i/9] |= bit; col_used[i%9] |= bit; box_used[(i/9/3)*3 + (i%9)/3] |= bit
    end
  end
  possible = Array.new(81, 0)
  81.times do |i|
    if grid[i] == 0
      r, c = i/9, i%9; b = (r/3)*3 + c/3
      possible[i] = 0x3FE & ~(row_used[r] | col_used[c] | box_used[b])
    end
  end
  solve(grid, row_used, col_used, box_used, possible)
end

puzzles = $stdin.readlines.map(&:strip).select { |l| l.length == 81 }
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
solved = puzzles.count { |p| init_and_solve(p) }
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
puts "solved: #{solved}/#{puzzles.length}"
puts "time: #{t1 - t0} ms"
