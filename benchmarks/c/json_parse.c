/* JSON parse benchmark — parse array of objects, sum "value" fields
 * Input: self-generated JSON string ~1MB
 * Format: [{"id":0,"value":100},{"id":1,"value":101},...]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define NUM_OBJECTS 50000

/* Generate JSON string in-memory */
static char *generate_json(int n, size_t *out_len) {
    /* Estimate: each object ~30 bytes, plus brackets/commas */
    size_t cap = (size_t)n * 40 + 16;
    char *buf = malloc(cap);
    size_t pos = 0;
    buf[pos++] = '[';
    for (int i = 0; i < n; i++) {
        if (i > 0) buf[pos++] = ',';
        pos += sprintf(buf + pos, "{\"id\":%d,\"value\":%d}", i, 100 + (i % 1000));
    }
    buf[pos++] = ']';
    buf[pos] = '\0';
    *out_len = pos;
    return buf;
}

/* Minimal JSON parser — extract "value" fields and sum them */
static int64_t parse_and_sum(const char *json, size_t len) {
    int64_t total = 0;
    const char *p = json;
    const char *end = json + len;
    /* Scan for "value": pattern */
    while (p < end - 8) {
        if (p[0] == '"' && p[1] == 'v' && p[2] == 'a' && p[3] == 'l'
            && p[4] == 'u' && p[5] == 'e' && p[6] == '"' && p[7] == ':') {
            p += 8;
            /* Parse integer */
            int64_t val = 0;
            int neg = 0;
            if (*p == '-') { neg = 1; p++; }
            while (p < end && *p >= '0' && *p <= '9') {
                val = val * 10 + (*p - '0');
                p++;
            }
            if (neg) val = -val;
            total += val;
        } else {
            p++;
        }
    }
    return total;
}

int main(void) {
    size_t len;
    char *json = generate_json(NUM_OBJECTS, &len);
    int64_t sum = parse_and_sum(json, len);
    printf("len=%zu sum=%ld\n", len, sum);
    free(json);
    return 0;
}
