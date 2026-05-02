package main

import (
	"fmt"
	"time"
)

const maxStates = 2048

// c: >=0 literal, -1 ANY, -2 SPLIT, -3 MATCH, -4 EPSILON
type State struct {
	c    int
	out1 int
	out2 int
}

var nfa [maxStates]State
var nstates int
var startState int

func newState(c, out1, out2 int) int {
	s := nstates
	nstates++
	nfa[s] = State{c, out1, out2}
	return s
}

var reStr []byte
var rePos int

func rePeek() int {
	if rePos >= len(reStr) {
		return 0
	}
	return int(reStr[rePos])
}
func reAdv() {
	if rePos < len(reStr) {
		rePos++
	}
}

type Frag struct{ start, end int }

func parseAtom() Frag {
	c := rePeek()
	if c == '(' {
		reAdv()
		f := parseExpr()
		if rePeek() == ')' {
			reAdv()
		}
		return f
	}
	if c == '.' {
		reAdv()
		s := newState(-1, -1, -1)
		j := newState(-4, -1, -1)
		nfa[s].out1 = j
		return Frag{s, j}
	}
	reAdv()
	s := newState(c, -1, -1)
	j := newState(-4, -1, -1)
	nfa[s].out1 = j
	return Frag{s, j}
}

func parseFactor() Frag {
	f := parseAtom()
	c := rePeek()
	if c == '*' {
		reAdv()
		sp := newState(-2, f.start, -1)
		j := newState(-4, -1, -1)
		nfa[f.end].out1 = sp
		nfa[sp].out2 = j
		return Frag{sp, j}
	}
	if c == '+' {
		reAdv()
		sp := newState(-2, f.start, -1)
		j := newState(-4, -1, -1)
		nfa[f.end].out1 = sp
		nfa[sp].out2 = j
		return Frag{f.start, j}
	}
	if c == '?' {
		reAdv()
		sp := newState(-2, f.start, -1)
		j := newState(-4, -1, -1)
		nfa[f.end].out1 = j
		nfa[sp].out2 = j
		return Frag{sp, j}
	}
	return f
}

func parseTerm() Frag {
	f := parseFactor()
	for rePeek() != 0 && rePeek() != ')' && rePeek() != '|' {
		f2 := parseFactor()
		nfa[f.end].out1 = f2.start
		f.end = f2.end
	}
	return f
}

func parseExpr() Frag {
	f := parseTerm()
	for rePeek() == '|' {
		reAdv()
		f2 := parseTerm()
		s := newState(-2, f.start, f2.start)
		j := newState(-4, -1, -1)
		nfa[f.end].out1 = j
		nfa[f2.end].out1 = j
		f = Frag{s, j}
	}
	return f
}

func compileRegex(pattern string) {
	nstates = 0
	reStr = []byte(pattern)
	rePos = 0
	f := parseExpr()
	accept := newState(-3, -1, -1)
	nfa[f.end].out1 = accept
	startState = f.start
}

var seen [maxStates]int
var gen int

func addState(list *[]int, s int) {
	if s < 0 || s >= nstates {
		return
	}
	if seen[s] == gen {
		return
	}
	seen[s] = gen
	if nfa[s].c == -2 {
		addState(list, nfa[s].out1)
		addState(list, nfa[s].out2)
		return
	}
	if nfa[s].c == -4 {
		addState(list, nfa[s].out1)
		return
	}
	*list = append(*list, s)
}

func matchNFA(str []byte) bool {
	gen++
	clist := make([]int, 0, 64)
	addState(&clist, startState)
	for _, ch := range str {
		gen++
		nlist := make([]int, 0, 64)
		for _, s := range clist {
			if nfa[s].c == int(ch) || nfa[s].c == -1 {
				addState(&nlist, nfa[s].out1)
			}
		}
		clist = nlist
		if len(clist) == 0 {
			return false
		}
	}
	for _, s := range clist {
		if nfa[s].c == -3 {
			return true
		}
	}
	return false
}

func genString(buf []byte, seed, length int) {
	rng := (int64(seed)*2654435761 + 1) & 0x7FFFFFFF
	for i := 0; i < length; i++ {
		rng = (rng*1103515245 + 12345 + int64(seed)) & 0x7FFFFFFF
		buf[i] = byte('a' + int(rng%26))
	}
}

func main() {
	patterns := []string{
		"a.*b.*c", "(ab|cd|ef)+", "a.b.c.d.e", "(a|b)(c|d)(e|f)",
		"ab*c+d?ef", ".*hello.*world.*", "(abc|def|ghi|jkl)+", "a.*a.*a.*a",
	}
	nstrings := 100000
	totalMatches := 0
	buf := make([]byte, 256)
	t0 := time.Now()
	for p, pat := range patterns {
		compileRegex(pat)
		matches := 0
		for i := 0; i < nstrings; i++ {
			ln := 10 + (i % 50)
			genString(buf, i+p*1000, ln)
			if matchNFA(buf[:ln]) {
				matches++
			}
		}
		totalMatches += matches
	}
	ms := time.Since(t0).Milliseconds()
	fmt.Printf("matches: %d\n", totalMatches)
	fmt.Printf("time: %d ms\n", ms)
}
