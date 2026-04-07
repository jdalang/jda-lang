#include <stdio.h>
#include <stdint.h>

volatile int64_t LIMIT = 100000000;

int main(void) {
    int64_t n = LIMIT;
    int64_t sum = 0;
    for (int64_t i = 0; i < n; i++) {
        sum += i;
    }
    printf("%ld\n", sum);
    return 0;
}
