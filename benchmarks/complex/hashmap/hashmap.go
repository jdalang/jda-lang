package main

import (
	"fmt"
	"time"
)

const tableSize = 1 << 20
const mask = tableSize - 1
const N = 600000

var tblKey [tableSize]int64
var tblVal [tableSize]int64

var rng int64 = 12345

func lcg() int64 {
	rng = (rng*1103515245 + 12345) & 2147483647
	return rng
}
func htHash(k int64) int64 { return (k * 2654435761) & mask }
func htInsert(k, v int64) {
	h := htHash(k)
	for tblKey[h] != 0 {
		if tblKey[h] == k { tblVal[h] = v; return }
		h = (h + 1) & mask
	}
	tblKey[h] = k; tblVal[h] = v
}
func htFind(k int64) int {
	h := htHash(k)
	for tblKey[h] != 0 {
		if tblKey[h] == k { return 1 }
		h = (h + 1) & mask
	}
	return 0
}

func main() {
	t0 := time.Now()
	rng = 12345
	for i := 0; i < N; i++ { k := lcg() | 1; htInsert(k, k+7) }
	rng = 12345
	var foundKnown int64
	for i := 0; i < N; i++ { k := lcg() | 1; foundKnown += int64(htFind(k)) }
	rng = 99999
	var foundRand int64
	for i := 0; i < N; i++ { k := lcg() | 1; foundRand += int64(htFind(k)) }
	ms := time.Since(t0).Milliseconds()
	fmt.Printf("inserted: %d\nfound_known: %d\nfound_rand: %d\ntime: %d ms\n",
		N, foundKnown, foundRand, ms)
}
