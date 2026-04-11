// JSON parse benchmark — parse array of objects, sum "value" fields
package main

import (
	"encoding/json"
	"fmt"
	"strings"
)

const numObjects = 50000

type Entry struct {
	ID    int `json:"id"`
	Value int `json:"value"`
}

func generateJSON(n int) string {
	var sb strings.Builder
	sb.Grow(n * 40)
	sb.WriteByte('[')
	for i := 0; i < n; i++ {
		if i > 0 {
			sb.WriteByte(',')
		}
		fmt.Fprintf(&sb, `{"id":%d,"value":%d}`, i, 100+(i%1000))
	}
	sb.WriteByte(']')
	return sb.String()
}

func main() {
	jsonStr := generateJSON(numObjects)
	var entries []Entry
	err := json.Unmarshal([]byte(jsonStr), &entries)
	if err != nil {
		panic(err)
	}
	sum := int64(0)
	for _, e := range entries {
		sum += int64(e.Value)
	}
	fmt.Printf("len=%d sum=%d\n", len(jsonStr), sum)
}
