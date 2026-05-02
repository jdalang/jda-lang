package main

import (
	"fmt"
	"time"
)

const windowSize = 4096
const lookahead = 258
const dataSize = 1024 * 1024

var rngState int64 = 42

func nextRand() int64 {
	rngState = (rngState*1103515245 + 12345) & 0x7FFFFFFF
	return rngState
}

func generateData() []byte {
	data := make([]byte, 0, dataSize)
	for len(data) < dataSize {
		r := nextRand()
		rm := r % 3
		if rm == 0 {
			data = append(data, byte('a'+nextRand()%26))
		} else if rm == 1 {
			l := 1 + int(nextRand()%8)
			for i := 0; i < l && len(data) < dataSize; i++ {
				data = append(data, byte('a'+nextRand()%26))
			}
		} else {
			if len(data) > 20 {
				src := int(nextRand() % int64(len(data)-1))
				l := 3 + int(nextRand()%20)
				for i := 0; i < l && len(data) < dataSize; i++ {
					dl := len(data)
					data = append(data, data[src+(i%(dl-src))])
				}
			} else {
				data = append(data, byte('a'+nextRand()%26))
			}
		}
	}
	return data[:dataSize]
}

func lz77Compress(src []byte) []byte {
	out := make([]byte, 0, len(src)*2)
	sp := 0
	for sp < len(src) {
		bestOff := 0
		bestLen := 0
		winStart := sp - windowSize
		if winStart < 0 {
			winStart = 0
		}
		for i := winStart; i < sp; i++ {
			l := 0
			maxLen := len(src) - sp - 1
			if maxLen > lookahead {
				maxLen = lookahead
			}
			for l < maxLen && src[i+l] == src[sp+l] {
				l++
			}
			if l > bestLen {
				bestLen = l
				bestOff = sp - i
			}
		}
		if bestLen >= 3 {
			out = append(out, 1, byte(bestOff>>8), byte(bestOff), byte(bestLen))
			sp += bestLen
			if sp < len(src) {
				out = append(out, src[sp])
				sp++
			} else {
				out = append(out, 0)
			}
		} else {
			out = append(out, 0, src[sp])
			sp++
		}
	}
	return out
}

func lz77Decompress(src []byte) []byte {
	out := make([]byte, 0, dataSize)
	sp := 0
	for sp < len(src) {
		if src[sp] == 1 {
			sp++
			offset := int(src[sp])<<8 | int(src[sp+1])
			sp += 2
			length := int(src[sp])
			sp++
			next := src[sp]
			sp++
			start := len(out) - offset
			for i := 0; i < length; i++ {
				out = append(out, out[start+i])
			}
			out = append(out, next)
		} else {
			sp++
			out = append(out, src[sp])
			sp++
		}
	}
	return out
}

func main() {
	rngState = 42
	data := generateData()
	t0 := time.Now()
	compressed := lz77Compress(data)
	decompressed := lz77Decompress(compressed)
	verified := len(decompressed) == len(data)
	if verified {
		for i := range data {
			if data[i] != decompressed[i] {
				verified = false
				break
			}
		}
	}
	ms := time.Since(t0).Milliseconds()
	vstr := "yes"
	if !verified {
		vstr = "no"
	}
	fmt.Printf("original: %d\n", dataSize)
	fmt.Printf("compressed: %d\n", len(compressed))
	fmt.Printf("ratio: %d%%\n", len(compressed)*100/dataSize)
	fmt.Printf("verified: %s\n", vstr)
	fmt.Printf("time: %d ms\n", ms)
}
