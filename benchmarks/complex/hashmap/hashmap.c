/* Hash map: open addressing, linear probing, 2^20 slots */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define TABLE_SIZE (1 << 20)
#define MASK       (TABLE_SIZE - 1)
#define N          600000

static long tbl[TABLE_SIZE * 2];  // [key, val] pairs; key=0 = empty
static long g_rng = 12345;

static long now_ms() {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}
static long lcg() { g_rng = (g_rng * 1103515245 + 12345) & 2147483647; return g_rng; }
static long ht_hash(long k) { return (k * 2654435761L) & MASK; }

static void ht_insert(long k, long v) {
    long h = ht_hash(k);
    while (tbl[h*2]) { if (tbl[h*2]==k){tbl[h*2+1]=v;return;} h=(h+1)&MASK; }
    tbl[h*2]=k; tbl[h*2+1]=v;
}
static int ht_find(long k) {
    long h = ht_hash(k);
    while (tbl[h*2]) { if (tbl[h*2]==k) return 1; h=(h+1)&MASK; }
    return 0;
}

int main() {
    long t0 = now_ms();
    g_rng = 12345;
    for (int i = 0; i < N; i++) { long k = lcg() | 1; ht_insert(k, k+7); }
    g_rng = 12345;
    long found_known = 0;
    for (int i = 0; i < N; i++) { long k = lcg() | 1; found_known += ht_find(k); }
    g_rng = 99999;
    long found_rand = 0;
    for (int i = 0; i < N; i++) { long k = lcg() | 1; found_rand += ht_find(k); }
    long t1 = now_ms();
    printf("inserted: %d\nfound_known: %ld\nfound_rand: %ld\ntime: %ld ms\n",
           N, found_known, found_rand, t1-t0);
    return 0;
}
