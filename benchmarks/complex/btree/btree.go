package main

import (
	"fmt"
	"time"
)

const order = 64
const maxKeys = order - 1

type Node struct {
	keys     [maxKeys]int32
	children [order]int32
	n        int
	isLeaf   bool
}

var nodes []Node

func newNode(leaf bool) int32 {
	id := int32(len(nodes))
	nd := Node{isLeaf: leaf}
	for i := range nd.children {
		nd.children[i] = -1
	}
	nodes = append(nodes, nd)
	return id
}

var root int32

func search(id int32, key int32) bool {
	if id < 0 {
		return false
	}
	nd := &nodes[id]
	i := 0
	for i < nd.n && key > nd.keys[i] {
		i++
	}
	if i < nd.n && key == nd.keys[i] {
		return true
	}
	if nd.isLeaf {
		return false
	}
	return search(nd.children[i], key)
}

func splitChild(parent int32, idx int) {
	full := nodes[parent].children[idx]
	mid := maxKeys / 2
	isLeaf := nodes[full].isLeaf
	right := newNode(isLeaf)

	rn := maxKeys - mid - 1
	for j := 0; j < rn; j++ {
		nodes[right].keys[j] = nodes[full].keys[mid+1+j]
	}
	if !isLeaf {
		for j := 0; j <= rn; j++ {
			nodes[right].children[j] = nodes[full].children[mid+1+j]
		}
	}
	promoteKey := nodes[full].keys[mid]
	nodes[full].n = mid
	nodes[right].n = rn

	pn := nodes[parent].n
	for j := pn; j > idx; j-- {
		nodes[parent].keys[j] = nodes[parent].keys[j-1]
		nodes[parent].children[j+1] = nodes[parent].children[j]
	}
	nodes[parent].keys[idx] = promoteKey
	nodes[parent].children[idx+1] = right
	nodes[parent].n++
}

func insertNonfull(id int32, key int32) {
	nd := &nodes[id]
	if nd.isLeaf {
		i := nd.n - 1
		for i >= 0 && key < nd.keys[i] {
			nd.keys[i+1] = nd.keys[i]
			i--
		}
		if i >= 0 && nd.keys[i] == key {
			return
		}
		nd.keys[i+1] = key
		nd.n++
	} else {
		i := nd.n - 1
		for i >= 0 && key < nd.keys[i] {
			i--
		}
		if i >= 0 && nd.keys[i] == key {
			return
		}
		i++
		ci := nd.children[i]
		if nodes[ci].n == maxKeys {
			splitChild(id, i)
			if key > nodes[id].keys[i] {
				i++
			}
			if i < nodes[id].n && key == nodes[id].keys[i] {
				return
			}
		}
		insertNonfull(nodes[id].children[i], key)
	}
}

func insert(key int32) {
	if nodes[root].n == maxKeys {
		s := newNode(false)
		nodes[s].children[0] = root
		root = s
		splitChild(s, 0)
		insertNonfull(s, key)
	} else {
		insertNonfull(root, key)
	}
}

var rngState int64 = 12345

func nextRand() int32 {
	rngState = (rngState*1103515245 + 12345) & 0x7FFFFFFF
	return int32(rngState)
}

func main() {
	n := int32(1000000)
	nodes = make([]Node, 0, 100000)
	root = newNode(true)

	t0 := time.Now()

	rngState = 12345
	for i := int32(0); i < n; i++ {
		insert(nextRand() % (n * 10))
	}

	rngState = 12345
	found := 0
	for i := int32(0); i < n; i++ {
		if search(root, nextRand()%(n*10)) {
			found++
		}
	}

	rngState = 99999
	found2 := 0
	for i := int32(0); i < n; i++ {
		if search(root, nextRand()%(n*10)) {
			found2++
		}
	}

	ms := time.Since(t0).Milliseconds()
	fmt.Printf("inserted: %d\n", n)
	fmt.Printf("found (known): %d\n", found)
	fmt.Printf("found (random): %d\n", found2)
	fmt.Printf("nodes: %d\n", len(nodes))
	fmt.Printf("time: %d ms\n", ms)
}
