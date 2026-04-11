/* LZ77 compression benchmark — compress + decompress 1MB of pseudo-random text
   Reports compressed size, round-trip verification, and timing */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define WINDOW_SIZE 4096
#define LOOKAHEAD 258
#define DATA_SIZE (1024 * 1024)
#define OUT_SIZE (DATA_SIZE * 2)

static unsigned char data[DATA_SIZE];
static unsigned char compressed[OUT_SIZE];
static unsigned char decompressed[DATA_SIZE];

static long rng_state = 42;
static int next_rand(void) {
    rng_state = (rng_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return (int)rng_state;
}

static void generate_data(void) {
    int pos = 0;
    while (pos < DATA_SIZE) {
        int r = next_rand();
        int rm = r % 3;
        if (rm == 0) {
            data[pos++] = 'a' + (next_rand() % 26);
        } else if (rm == 1) {
            int len = 1 + next_rand() % 8;
            for (int i = 0; i < len && pos < DATA_SIZE; i++) {
                data[pos++] = 'a' + (next_rand() % 26);
            }
        } else {
            if (pos > 20) {
                int src = next_rand() % (pos - 1);
                int len = 3 + next_rand() % 20;
                for (int i = 0; i < len && pos < DATA_SIZE; i++) {
                    int idx = src + (i % (pos - src));
                    data[pos] = data[idx];
                    pos++;
                }
            } else {
                data[pos++] = 'a' + (next_rand() % 26);
            }
        }
    }
}

/* LZ77 compress: output (offset, length, next_char) triples as bytes
   Format: if match found: [1][offset_hi][offset_lo][length][next_char]
           if no match:    [0][literal_char] */
static int lz77_compress(const unsigned char *src, int src_len,
                         unsigned char *dst, int dst_cap) {
    int sp = 0, dp = 0;
    while (sp < src_len && dp + 5 < dst_cap) {
        int best_off = 0, best_len = 0;
        int win_start = sp - WINDOW_SIZE;
        if (win_start < 0) win_start = 0;

        for (int i = win_start; i < sp; i++) {
            int len = 0;
            int max_len = src_len - sp - 1;
            if (max_len > LOOKAHEAD) max_len = LOOKAHEAD;
            while (len < max_len && src[i + len] == src[sp + len]) {
                len++;
            }
            if (len > best_len) {
                best_len = len;
                best_off = sp - i;
            }
        }

        if (best_len >= 3) {
            dst[dp++] = 1;
            dst[dp++] = (best_off >> 8) & 0xFF;
            dst[dp++] = best_off & 0xFF;
            dst[dp++] = best_len & 0xFF;
            sp += best_len;
            if (sp < src_len) {
                dst[dp++] = src[sp++];
            } else {
                dst[dp++] = 0;
            }
        } else {
            dst[dp++] = 0;
            dst[dp++] = src[sp++];
        }
    }
    return dp;
}

/* LZ77 decompress */
static int lz77_decompress(const unsigned char *src, int src_len,
                           unsigned char *dst, int dst_cap) {
    int sp = 0, dp = 0;
    while (sp < src_len && dp < dst_cap) {
        if (src[sp] == 1) {
            sp++;
            int offset = (src[sp] << 8) | src[sp+1];
            sp += 2;
            int length = src[sp++];
            unsigned char next = src[sp++];

            int start = dp - offset;
            for (int i = 0; i < length && dp < dst_cap; i++) {
                dst[dp++] = dst[start + i];
            }
            if (dp < dst_cap) {
                dst[dp++] = next;
            }
        } else {
            sp++;
            dst[dp++] = src[sp++];
        }
    }
    return dp;
}

int main(void) {
    generate_data();

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    /* Compress */
    int comp_size = lz77_compress(data, DATA_SIZE, compressed, OUT_SIZE);

    /* Decompress */
    int decomp_size = lz77_decompress(compressed, comp_size, decompressed, DATA_SIZE);

    /* Verify */
    int match = 1;
    if (decomp_size != DATA_SIZE) match = 0;
    else {
        for (int i = 0; i < DATA_SIZE; i++) {
            if (data[i] != decompressed[i]) { match = 0; break; }
        }
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    long ms = (t1.tv_sec - t0.tv_sec)*1000 + (t1.tv_nsec - t0.tv_nsec)/1000000;

    printf("original: %d\n", DATA_SIZE);
    printf("compressed: %d\n", comp_size);
    printf("ratio: %d%%\n", comp_size * 100 / DATA_SIZE);
    printf("verified: %s\n", match ? "yes" : "no");
    printf("time: %ld ms\n", ms);
    return 0;
}
