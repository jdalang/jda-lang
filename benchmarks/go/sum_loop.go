package main

import "fmt"

func main() {
	var sum int64 = 0
	var i int64
	for i = 0; i < 100000000; i++ {
		sum += i
	}
	fmt.Println(sum)
}
