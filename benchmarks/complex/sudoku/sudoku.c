/* Sudoku solver — constraint propagation + backtracking (MRV heuristic)
   Reads puzzles from stdin, one per line, 81 chars each */
#include <stdio.h>
#include <string.h>
#include <time.h>

static int grid[81];
static int possible[81];
static int row_used[9], col_used[9], box_used[9];

static void init_board(const char *puzzle) {
    memset(row_used, 0, sizeof(row_used));
    memset(col_used, 0, sizeof(col_used));
    memset(box_used, 0, sizeof(box_used));
    for (int i = 0; i < 81; i++) {
        if (puzzle[i] >= '1' && puzzle[i] <= '9') {
            int v = puzzle[i] - '0';
            grid[i] = v;
            int bit = 1 << v;
            row_used[i / 9] |= bit;
            col_used[i % 9] |= bit;
            box_used[(i / 9 / 3) * 3 + (i % 9) / 3] |= bit;
        } else {
            grid[i] = 0;
        }
    }
    for (int i = 0; i < 81; i++) {
        if (grid[i] == 0) {
            int r = i / 9, c = i % 9, b = (r / 3) * 3 + c / 3;
            possible[i] = 0x3FE & ~(row_used[r] | col_used[c] | box_used[b]);
        } else {
            possible[i] = 0;
        }
    }
}

static int count_bits(int x) {
    int c = 0;
    while (x) { c += x & 1; x >>= 1; }
    return c;
}

static int solve(void) {
    int best = -1, best_count = 10;
    for (int i = 0; i < 81; i++) {
        if (grid[i] == 0) {
            int cnt = count_bits(possible[i]);
            if (cnt == 0) return 0;
            if (cnt < best_count) { best = i; best_count = cnt; }
        }
    }
    if (best == -1) return 1;

    int r = best / 9, c = best % 9, b = (r / 3) * 3 + c / 3;
    int saved_poss[81];
    memcpy(saved_poss, possible, sizeof(possible));
    int saved_row[9], saved_col[9], saved_box[9];
    memcpy(saved_row, row_used, sizeof(row_used));
    memcpy(saved_col, col_used, sizeof(col_used));
    memcpy(saved_box, box_used, sizeof(box_used));

    int bits = possible[best];
    for (int v = 1; v <= 9; v++) {
        if (!(bits & (1 << v))) continue;
        int bit = 1 << v;
        grid[best] = v;
        row_used[r] |= bit; col_used[c] |= bit; box_used[b] |= bit;
        for (int i = 0; i < 81; i++) {
            if (grid[i] == 0) {
                int ri = i / 9, ci = i % 9, bi = (ri / 3) * 3 + ci / 3;
                possible[i] = 0x3FE & ~(row_used[ri] | col_used[ci] | box_used[bi]);
            }
        }
        if (solve()) return 1;
        grid[best] = 0;
        memcpy(row_used, saved_row, sizeof(row_used));
        memcpy(col_used, saved_col, sizeof(col_used));
        memcpy(box_used, saved_box, sizeof(box_used));
        memcpy(possible, saved_poss, sizeof(possible));
    }
    return 0;
}

int main(void) {
    char line[256];
    char puzzles[1000][82];
    int npuzzles = 0;
    while (npuzzles < 1000 && fgets(line, sizeof(line), stdin)) {
        int len = strlen(line);
        while (len > 0 && (line[len-1] == '\n' || line[len-1] == '\r')) line[--len] = 0;
        if (len == 81) {
            memcpy(puzzles[npuzzles], line, 82);
            npuzzles++;
        }
    }

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    int solved = 0;
    for (int p = 0; p < npuzzles; p++) {
        init_board(puzzles[p]);
        if (solve()) solved++;
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    long ms = (t1.tv_sec - t0.tv_sec) * 1000 + (t1.tv_nsec - t0.tv_nsec) / 1000000;
    printf("solved: %d/%d\n", solved, npuzzles);
    printf("time: %ld ms\n", ms);
    return 0;
}
