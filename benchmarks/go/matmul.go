package main

import "fmt"

const N = 200

func main() {
	a := make([]int64, N*N)
	b := make([]int64, N*N)
	c := make([]int64, N*N)

	for i := 0; i < N; i++ {
		for j := 0; j < N; j++ {
			a[i*N+j] = int64(i + j)
			b[i*N+j] = int64(i*j + 1)
		}
	}

	for i := 0; i < N; i++ {
		for j := 0; j < N; j++ {
			var sum int64 = 0
			for k := 0; k < N; k++ {
				sum += a[i*N+k] * b[k*N+j]
			}
			c[i*N+j] = sum
		}
	}

	fmt.Println(c[99*N+99])
}
