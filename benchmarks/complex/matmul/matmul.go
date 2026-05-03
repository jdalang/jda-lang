package main

import ("fmt"; "time")

const N = 256
var A, B, C [N][N]int64

func main() {
	for i := 0; i < N; i++ { for j := 0; j < N; j++ {
		A[i][j]=int64((i*7+j*13+1)%100); B[i][j]=int64((i*11+j*5+3)%100)
	}}
	t0 := time.Now()
	for i := 0; i < N; i++ { for j := 0; j < N; j++ {
		var s int64; for k := 0; k < N; k++ { s += A[i][k]*B[k][j] }; C[i][j]=s
	}}
	ms := time.Since(t0).Milliseconds()
	var chk int64
	for i := 0; i < N; i++ { for j := 0; j < N; j++ { chk=(chk+C[i][j])%1000000007 }}
	fmt.Printf("n: %d\nchecksum: %d\ntime: %d ms\n", N, chk, ms)
}
