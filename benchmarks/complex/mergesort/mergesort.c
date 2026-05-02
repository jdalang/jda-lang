/* Merge sort: 2M integers, bottom-up iterative */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#define N 2000000
static long arr[N], tmp[N];
static long rng = 42;

static long now_ms() {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}
static long lcg() { rng=(rng*1103515245+12345)&2147483647; return rng; }

static void merge_run(long lo, long mid, long hi) {
    long i=lo, j=mid, k=lo;
    while (k < hi) {
        if (i < mid && (j >= hi || arr[i] <= arr[j])) tmp[k++] = arr[i++];
        else tmp[k++] = arr[j++];
    }
    for (long x=lo; x<hi; x++) arr[x]=tmp[x];
}

int main() {
    for (int i=0;i<N;i++) arr[i]=lcg();
    long t0=now_ms();
    for (long w=1;w<N;w*=2)
        for (long lo=0;lo<N;lo+=2*w) {
            long mid=lo+w; if(mid>N)mid=N;
            long hi=lo+2*w; if(hi>N)hi=N;
            if (mid<hi) merge_run(lo,mid,hi);
        }
    long t1=now_ms();
    int ok=1; for(int i=1;i<N;i++) if(arr[i]<arr[i-1]){ok=0;break;}
    long chk=0; for(int i=0;i<N;i++) chk=(chk+arr[i])&0xffffffff;
    printf("n: %d\nsorted: %d\nfirst: %ld\nlast: %ld\nchecksum: %ld\ntime: %ld ms\n",
           N,ok,arr[0],arr[N-1],chk,t1-t0);
    return 0;
}
