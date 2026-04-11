/* NFA regex engine — Thompson construction, 8 patterns × 100K strings */
use std::time::Instant;

const MAX_STATES: usize = 2048;

/* c: >=0 literal, -1 ANY, -2 SPLIT, -3 MATCH, -4 EPSILON */
#[derive(Clone, Copy)]
struct State { c: i32, out1: i32, out2: i32 }

static mut NFA: [State; MAX_STATES] = [State { c: 0, out1: -1, out2: -1 }; MAX_STATES];
static mut NSTATES: usize = 0;
static mut START: usize = 0;

unsafe fn new_state(c: i32, out1: i32, out2: i32) -> usize {
    let s = NSTATES; NSTATES += 1;
    NFA[s] = State { c, out1, out2 };
    s
}

struct Parser { pat: Vec<u8>, pos: usize }

impl Parser {
    fn peek(&self) -> u8 { if self.pos < self.pat.len() { self.pat[self.pos] } else { 0 } }
    fn adv(&mut self) { if self.pos < self.pat.len() { self.pos += 1; } }

    unsafe fn parse_atom(&mut self) -> (usize, usize) {
        let c = self.peek();
        if c == b'(' {
            self.adv(); let f = self.parse_expr();
            if self.peek() == b')' { self.adv(); }
            return f;
        }
        if c == b'.' {
            self.adv();
            let s = new_state(-1, -1, -1);
            let j = new_state(-4, -1, -1);
            NFA[s].out1 = j as i32;
            return (s, j);
        }
        self.adv();
        let s = new_state(c as i32, -1, -1);
        let j = new_state(-4, -1, -1);
        NFA[s].out1 = j as i32;
        (s, j)
    }

    unsafe fn parse_factor(&mut self) -> (usize, usize) {
        let (fs, fe) = self.parse_atom();
        let c = self.peek();
        if c == b'*' {
            self.adv();
            let sp = new_state(-2, fs as i32, -1);
            let j = new_state(-4, -1, -1);
            NFA[fe].out1 = sp as i32;
            NFA[sp].out2 = j as i32;
            return (sp, j);
        }
        if c == b'+' {
            self.adv();
            let sp = new_state(-2, fs as i32, -1);
            let j = new_state(-4, -1, -1);
            NFA[fe].out1 = sp as i32;
            NFA[sp].out2 = j as i32;
            return (fs, j);
        }
        if c == b'?' {
            self.adv();
            let sp = new_state(-2, fs as i32, -1);
            let j = new_state(-4, -1, -1);
            NFA[fe].out1 = j as i32;
            NFA[sp].out2 = j as i32;
            return (sp, j);
        }
        (fs, fe)
    }

    unsafe fn parse_term(&mut self) -> (usize, usize) {
        let (mut fs, mut fe) = self.parse_factor();
        while self.peek() != 0 && self.peek() != b')' && self.peek() != b'|' {
            let (s2, e2) = self.parse_factor();
            NFA[fe].out1 = s2 as i32;
            fe = e2;
        }
        (fs, fe)
    }

    unsafe fn parse_expr(&mut self) -> (usize, usize) {
        let (mut fs, mut fe) = self.parse_term();
        while self.peek() == b'|' {
            self.adv();
            let (s2, e2) = self.parse_term();
            let s = new_state(-2, fs as i32, s2 as i32);
            let j = new_state(-4, -1, -1);
            NFA[fe].out1 = j as i32;
            NFA[e2].out1 = j as i32;
            fs = s; fe = j;
        }
        (fs, fe)
    }
}

unsafe fn compile_regex(pattern: &str) {
    NSTATES = 0;
    let mut p = Parser { pat: pattern.as_bytes().to_vec(), pos: 0 };
    let (fs, fe) = p.parse_expr();
    let accept = new_state(-3, -1, -1);
    NFA[fe].out1 = accept as i32;
    START = fs;
}

static mut SEEN: [i32; MAX_STATES] = [0; MAX_STATES];
static mut GEN: i32 = 0;

unsafe fn add_state(list: &mut Vec<usize>, s: i32) {
    if s < 0 || s as usize >= NSTATES { return; }
    let su = s as usize;
    if SEEN[su] == GEN { return; }
    SEEN[su] = GEN;
    if NFA[su].c == -2 { add_state(list, NFA[su].out1); add_state(list, NFA[su].out2); return; }
    if NFA[su].c == -4 { add_state(list, NFA[su].out1); return; }
    list.push(su);
}

unsafe fn match_nfa(s: &[u8]) -> bool {
    GEN += 1;
    let mut clist = Vec::with_capacity(64);
    add_state(&mut clist, START as i32);
    for &ch in s {
        GEN += 1;
        let mut nlist = Vec::with_capacity(64);
        for &st in &clist {
            if NFA[st].c == ch as i32 || NFA[st].c == -1 {
                add_state(&mut nlist, NFA[st].out1);
            }
        }
        clist = nlist;
        if clist.is_empty() { return false; }
    }
    clist.iter().any(|&st| NFA[st].c == -3)
}

fn gen_string(buf: &mut [u8], seed: usize, len: usize) {
    let mut rng: i64 = ((seed as i64).wrapping_mul(2654435761) + 1) & 0x7FFFFFFF;
    for i in 0..len {
        rng = (rng.wrapping_mul(1103515245).wrapping_add(12345).wrapping_add(seed as i64)) & 0x7FFFFFFF;
        buf[i] = b'a' + (rng % 26) as u8;
    }
}

fn main() {
    let patterns = [
        "a.*b.*c", "(ab|cd|ef)+", "a.b.c.d.e", "(a|b)(c|d)(e|f)",
        "ab*c+d?ef", ".*hello.*world.*", "(abc|def|ghi|jkl)+", "a.*a.*a.*a",
    ];
    let nstrings = 100000;
    let mut total_matches = 0;
    let mut buf = [0u8; 256];
    let t0 = Instant::now();
    for (p_idx, pat) in patterns.iter().enumerate() {
        unsafe { compile_regex(pat); }
        let mut matches = 0;
        for i in 0..nstrings {
            let len = 10 + (i % 50);
            gen_string(&mut buf, i + p_idx * 1000, len);
            if unsafe { match_nfa(&buf[..len]) } { matches += 1; }
        }
        total_matches += matches;
    }
    let ms = t0.elapsed().as_millis();
    println!("matches: {}", total_matches);
    println!("time: {} ms", ms);
}
