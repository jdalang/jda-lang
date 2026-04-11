use std::io::{self, BufRead};
use std::time::Instant;

static mut GRID: [i32; 81] = [0; 81];
static mut POSSIBLE: [i32; 81] = [0; 81];
static mut ROW_USED: [i32; 9] = [0; 9];
static mut COL_USED: [i32; 9] = [0; 9];
static mut BOX_USED: [i32; 9] = [0; 9];

fn count_bits(mut x: i32) -> i32 {
    let mut c = 0;
    while x != 0 { c += x & 1; x >>= 1; }
    c
}

unsafe fn init_board(puzzle: &[u8]) {
    ROW_USED = [0; 9]; COL_USED = [0; 9]; BOX_USED = [0; 9];
    for i in 0..81 {
        if puzzle[i] >= b'1' && puzzle[i] <= b'9' {
            let v = (puzzle[i] - b'0') as i32;
            GRID[i] = v;
            let bit = 1 << v;
            ROW_USED[i / 9] |= bit; COL_USED[i % 9] |= bit;
            BOX_USED[(i / 9 / 3) * 3 + (i % 9) / 3] |= bit;
        } else {
            GRID[i] = 0;
        }
    }
    for i in 0..81 {
        if GRID[i] == 0 {
            let (r, c) = (i / 9, i % 9);
            let b = (r / 3) * 3 + c / 3;
            POSSIBLE[i] = 0x3FE & !(ROW_USED[r] | COL_USED[c] | BOX_USED[b]);
        } else {
            POSSIBLE[i] = 0;
        }
    }
}

unsafe fn solve() -> bool {
    let (mut best, mut best_count) = (-1i32, 10);
    for i in 0..81 {
        if GRID[i] == 0 {
            let cnt = count_bits(POSSIBLE[i]);
            if cnt == 0 { return false; }
            if cnt < best_count { best = i as i32; best_count = cnt; }
        }
    }
    if best == -1 { return true; }
    let bi = best as usize;
    let (r, c) = (bi / 9, bi % 9);
    let b = (r / 3) * 3 + c / 3;
    let saved_p = POSSIBLE; let saved_r = ROW_USED;
    let saved_c = COL_USED; let saved_b = BOX_USED;
    let bits = POSSIBLE[bi];
    for v in 1..=9 {
        if bits & (1 << v) == 0 { continue; }
        let bit = 1 << v;
        GRID[bi] = v;
        ROW_USED[r] |= bit; COL_USED[c] |= bit; BOX_USED[b] |= bit;
        for i in 0..81 {
            if GRID[i] == 0 {
                let (ri, ci) = (i / 9, i % 9);
                let bxi = (ri / 3) * 3 + ci / 3;
                POSSIBLE[i] = 0x3FE & !(ROW_USED[ri] | COL_USED[ci] | BOX_USED[bxi]);
            }
        }
        if solve() { return true; }
        GRID[bi] = 0;
        POSSIBLE = saved_p; ROW_USED = saved_r;
        COL_USED = saved_c; BOX_USED = saved_b;
    }
    false
}

fn main() {
    let stdin = io::stdin();
    let puzzles: Vec<String> = stdin.lock().lines()
        .filter_map(|l| l.ok())
        .map(|l| l.trim().to_string())
        .filter(|l| l.len() == 81)
        .collect();
    let t0 = Instant::now();
    let mut solved = 0;
    for p in &puzzles {
        unsafe {
            init_board(p.as_bytes());
            if solve() { solved += 1; }
        }
    }
    let ms = t0.elapsed().as_millis();
    println!("solved: {}/{}", solved, puzzles.len());
    println!("time: {} ms", ms);
}
