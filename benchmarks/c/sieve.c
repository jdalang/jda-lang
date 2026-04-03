#include <stdio.h>
#include <stdint.h>
#include <string.h>

int main(void) {
    int64_t limit = 100000;
    char sieve[100001];
    memset(sieve, 0, sizeof(sieve));
    for (int64_t i = 2; i * i <= limit; i++) {
        if (sieve[i] == 0) {
            for (int64_t j = i * i; j <= limit; j += i) {
                sieve[j] = 1;
            }
        }
    }
    int64_t count = 0;
    for (int64_t i = 2; i <= limit; i++) {
        if (sieve[i] == 0) count++;
    }
    printf("%ld\n", count);
    return 0;
}
