#include <stdio.h>
#include <stdint.h>

int main(void) {
    int64_t sum = 0;
    for (int64_t i = 1; i <= 100000000; i++) {
        sum += i;
    }
    printf("%ld\n", sum);
    return 0;
}
