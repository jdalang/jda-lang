/* Matrix multiply: 256x256 integers */
#include <stdio.h>
#include <time.h>

#define N 256
static long A[N][N], B[N][N], C[N][N];

static long now_ms() {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec*1000 + ts.tv_nsec/1000000;
}

int main() {
    for (int i=0;i<N;i++) for (int j=0;j<N;j++) {
        A[i][j]=(i*7+j*13+1)%100; B[i][j]=(i*11+j*5+3)%100;
    }
    long t0=now_ms();
    for (int i=0;i<N;i++) for (int j=0;j<N;j++) {
        long s=0; for (int k=0;k<N;k++) s+=A[i][k]*B[k][j]; C[i][j]=s;
    }
    long t1=now_ms();
    long mod=1000000007, chk=0;
    for (int i=0;i<N;i++) for (int j=0;j<N;j++) chk=(chk+C[i][j])%mod;
    printf("n: %d\nchecksum: %ld\ntime: %ld ms\n", N, chk, t1-t0);
    return 0;
}
