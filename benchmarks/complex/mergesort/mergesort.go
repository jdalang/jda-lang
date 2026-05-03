package main

import (
	"fmt"
	"time"
)

const N = 2000000

var arr [N]int64
var tmp [N]int64
var rng int64 = 42

func lcg() int64 { rng = (rng*1103515245 + 12345) & 2147483647; return rng }

func mergeRun(lo, mid, hi int) {
	i, j, k := lo, mid, lo
	for k < hi {
		if i < mid && (j >= hi || arr[i] <= arr[j]) { tmp[k] = arr[i]; i++ } else { tmp[k] = arr[j]; j++ }
		k++
	}
	for x := lo; x < hi; x++ { arr[x] = tmp[x] }
}

func main() {
	for i := 0; i < N; i++ { arr[i] = lcg() }
	t0 := time.Now()
	for w := 1; w < N; w *= 2 {
		for lo := 0; lo < N; lo += 2 * w {
			mid := lo + w; if mid > N { mid = N }
			hi := lo + 2*w; if hi > N { hi = N }
			if mid < hi { mergeRun(lo, mid, hi) }
		}
	}
	ms := time.Since(t0).Milliseconds()
	ok := 1; for i := 1; i < N; i++ { if arr[i] < arr[i-1] { ok = 0; break } }
	var chk int64; for i := 0; i < N; i++ { chk = (chk + arr[i]) & 0xffffffff }
	fmt.Printf("n: %d\nsorted: %d\nfirst: %d\nlast: %d\nchecksum: %d\ntime: %d ms\n",
		N, ok, arr[0], arr[N-1], chk, ms)
}
