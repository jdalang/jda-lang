#include <stdio.h>
#include <stdint.h>

#define N 200

int64_t a[N*N], b[N*N], c[N*N];

int main(void) {
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++) {
            a[i*N+j] = i + j;
            b[i*N+j] = i * j + 1;
            c[i*N+j] = 0;
        }

    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++) {
            int64_t sum = 0;
            for (int k = 0; k < N; k++)
                sum += a[i*N+k] * b[k*N+j];
            c[i*N+j] = sum;
        }

    printf("%ld\n", c[99*N+99]);
    return 0;
}
