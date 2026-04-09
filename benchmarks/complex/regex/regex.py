import time

MAX_STATES = 2048
# c: >=0 literal, -1 ANY, -2 SPLIT, -3 MATCH, -4 EPSILON
nfa = []  # [c, out1, out2]
nstates = 0
start_state = 0

def new_state(c, out1, out2):
    global nstates
    s = nstates; nstates += 1
    nfa.append([c, out1, out2])
    return s

class Parser:
    def __init__(self, pat):
        self.pat = pat; self.pos = 0
    def peek(self):
        return ord(self.pat[self.pos]) if self.pos < len(self.pat) else 0
    def adv(self):
        if self.pos < len(self.pat): self.pos += 1

    def parse_atom(self):
        c = self.peek()
        if c == 40:  # (
            self.adv(); f = self.parse_expr()
            if self.peek() == 41: self.adv()
            return f
        if c == 46:  # .
            self.adv(); s = new_state(-1, -1, -1); j = new_state(-4, -1, -1)
            nfa[s][1] = j; return (s, j)
        self.adv()
        s = new_state(c, -1, -1); j = new_state(-4, -1, -1)
        nfa[s][1] = j; return (s, j)

    def parse_factor(self):
        fs, fe = self.parse_atom()
        c = self.peek()
        if c == 42:  # *
            self.adv(); sp = new_state(-2, fs, -1); j = new_state(-4, -1, -1)
            nfa[fe][1] = sp; nfa[sp][2] = j; return (sp, j)
        if c == 43:  # +
            self.adv(); sp = new_state(-2, fs, -1); j = new_state(-4, -1, -1)
            nfa[fe][1] = sp; nfa[sp][2] = j; return (fs, j)
        if c == 63:  # ?
            self.adv(); sp = new_state(-2, fs, -1); j = new_state(-4, -1, -1)
            nfa[fe][1] = j; nfa[sp][2] = j; return (sp, j)
        return (fs, fe)

    def parse_term(self):
        fs, fe = self.parse_factor()
        while self.peek() != 0 and self.peek() != 41 and self.peek() != 124:
            s2, e2 = self.parse_factor()
            nfa[fe][1] = s2; fe = e2
        return (fs, fe)

    def parse_expr(self):
        fs, fe = self.parse_term()
        while self.peek() == 124:  # |
            self.adv(); s2, e2 = self.parse_term()
            s = new_state(-2, fs, s2); j = new_state(-4, -1, -1)
            nfa[fe][1] = j; nfa[e2][1] = j
            fs, fe = s, j
        return (fs, fe)

def compile_regex(pattern):
    global nfa, nstates, start_state
    nfa = []; nstates = 0
    p = Parser(pattern)
    fs, fe = p.parse_expr()
    accept = new_state(-3, -1, -1)
    nfa[fe][1] = accept
    start_state = fs

seen = [0] * MAX_STATES
gen = 0

def add_state(lst, s):
    global gen
    if s < 0 or s >= nstates: return
    if seen[s] == gen: return
    seen[s] = gen
    if nfa[s][0] == -2: add_state(lst, nfa[s][1]); add_state(lst, nfa[s][2]); return
    if nfa[s][0] == -4: add_state(lst, nfa[s][1]); return
    lst.append(s)

def match_nfa(s):
    global gen
    gen += 1; clist = []; add_state(clist, start_state)
    for ch in s:
        gen += 1; nlist = []
        for st in clist:
            if nfa[st][0] == ch or nfa[st][0] == -1:
                add_state(nlist, nfa[st][1])
        clist = nlist
        if not clist: return False
    return any(nfa[st][0] == -3 for st in clist)

def gen_string(seed, length):
    rng = (seed * 2654435761 + 1) & 0x7FFFFFFF
    out = bytearray(length)
    for i in range(length):
        rng = (rng * 1103515245 + 12345 + seed) & 0x7FFFFFFF
        out[i] = 97 + rng % 26
    return bytes(out)

patterns = [
    "a.*b.*c", "(ab|cd|ef)+", "a.b.c.d.e", "(a|b)(c|d)(e|f)",
    "ab*c+d?ef", ".*hello.*world.*", "(abc|def|ghi|jkl)+", "a.*a.*a.*a",
]
nstrings = 100000
total_matches = 0
t0 = time.monotonic()
for p_idx, pat in enumerate(patterns):
    compile_regex(pat)
    matches = 0
    for i in range(nstrings):
        ln = 10 + (i % 50)
        s = gen_string(i + p_idx * 1000, ln)
        if match_nfa(s): matches += 1
    total_matches += matches
ms = int((time.monotonic() - t0) * 1000)
print(f"matches: {total_matches}")
print(f"time: {ms} ms")
