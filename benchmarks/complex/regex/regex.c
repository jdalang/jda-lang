/* Regex engine — NFA-based, Thompson construction
   Supports: . * + ? | () concatenation
   Generates random-ish strings and counts matches */
#include <stdio.h>
#include <string.h>
#include <time.h>

#define MAX_STATES 2048

/* c values: >=0 = literal char, -1 = ANY (dot), -2 = SPLIT, -3 = MATCH, -4 = EPSILON */
typedef struct { int c; int out1; int out2; } State;
static State nfa[MAX_STATES];
static int nstates;
static int start_state;

static int new_state(int c, int out1, int out2) {
    int s = nstates++;
    nfa[s].c = c; nfa[s].out1 = out1; nfa[s].out2 = out2;
    return s;
}

static const char *re_str;
static int re_pos;
static int re_peek(void) { return re_str[re_pos] ? re_str[re_pos] : 0; }
static void re_adv(void) { if (re_str[re_pos]) re_pos++; }

/* Fragment: start state + end state. end.out1 is always -1 (the dangling arrow) */
typedef struct { int start; int end; } Frag;

static Frag parse_expr(void);

static Frag parse_atom(void) {
    int c = re_peek();
    if (c == '(') {
        re_adv();
        Frag f = parse_expr();
        if (re_peek() == ')') re_adv();
        return f;
    }
    if (c == '.') {
        re_adv();
        int s = new_state(-1, -1, -1);
        int join = new_state(-4, -1, -1);
        nfa[s].out1 = join;
        return (Frag){s, join};
    }
    re_adv();
    int s = new_state(c, -1, -1);
    int join = new_state(-4, -1, -1);
    nfa[s].out1 = join;
    return (Frag){s, join};
}

static Frag parse_factor(void) {
    Frag f = parse_atom();
    int c = re_peek();
    if (c == '*') {
        re_adv();
        /* split -> body or skip; body loops back to split */
        int split = new_state(-2, f.start, -1);
        int join = new_state(-4, -1, -1);
        nfa[f.end].out1 = split; /* loop back */
        nfa[split].out2 = join;  /* skip */
        return (Frag){split, join};
    }
    if (c == '+') {
        re_adv();
        /* body then split(loop or done) */
        int split = new_state(-2, f.start, -1);
        int join = new_state(-4, -1, -1);
        nfa[f.end].out1 = split;
        nfa[split].out2 = join;
        return (Frag){f.start, join};
    }
    if (c == '?') {
        re_adv();
        int split = new_state(-2, f.start, -1);
        int join = new_state(-4, -1, -1);
        nfa[f.end].out1 = join;
        nfa[split].out2 = join;
        return (Frag){split, join};
    }
    return f;
}

static Frag parse_term(void) {
    Frag f = parse_factor();
    while (re_peek() && re_peek() != ')' && re_peek() != '|') {
        Frag f2 = parse_factor();
        nfa[f.end].out1 = f2.start; /* patch dangling arrow */
        f.end = f2.end;
    }
    return f;
}

static Frag parse_expr(void) {
    Frag f = parse_term();
    while (re_peek() == '|') {
        re_adv();
        Frag f2 = parse_term();
        int s = new_state(-2, f.start, f2.start);
        int join = new_state(-4, -1, -1);
        nfa[f.end].out1 = join;
        nfa[f2.end].out1 = join;
        f = (Frag){s, join};
    }
    return f;
}

static void compile_regex(const char *pattern) {
    nstates = 0;
    re_str = pattern;
    re_pos = 0;
    Frag f = parse_expr();
    int accept = new_state(-3, -1, -1);
    nfa[f.end].out1 = accept;
    start_state = f.start;
}

/* NFA simulation */
static int clist[MAX_STATES], nlist_buf[MAX_STATES];
static int clen, nlen;
static int seen[MAX_STATES];
static int gen;

static void add_state(int *list, int *len, int s) {
    if (s < 0 || s >= nstates) return;
    if (seen[s] == gen) return;
    seen[s] = gen;
    if (nfa[s].c == -2) { /* SPLIT */
        add_state(list, len, nfa[s].out1);
        add_state(list, len, nfa[s].out2);
        return;
    }
    if (nfa[s].c == -4) { /* EPSILON */
        add_state(list, len, nfa[s].out1);
        return;
    }
    list[(*len)++] = s;
}

static int match_nfa(const char *str) {
    gen++;
    clen = 0;
    add_state(clist, &clen, start_state);

    for (int i = 0; str[i]; i++) {
        int ch = (unsigned char)str[i];
        gen++;
        nlen = 0;
        for (int j = 0; j < clen; j++) {
            int s = clist[j];
            if (nfa[s].c == ch || nfa[s].c == -1) {
                add_state(nlist_buf, &nlen, nfa[s].out1);
            }
        }
        for (int k = 0; k < nlen; k++) clist[k] = nlist_buf[k];
        clen = nlen;
        if (clen == 0) return 0;
    }
    for (int j = 0; j < clen; j++) {
        if (nfa[clist[j]].c == -3) return 1;
    }
    return 0;
}

static char strbuf[256];
static long str_rng;
static void gen_string(int seed, int len) {
    str_rng = ((long)seed * 2654435761L + 1) & 0x7FFFFFFF;
    for (int i = 0; i < len; i++) {
        str_rng = (str_rng * 1103515245 + 12345 + (long)seed) & 0x7FFFFFFF;
        strbuf[i] = 'a' + (int)(str_rng % 26);
    }
    strbuf[len] = 0;
}

int main(void) {
    const char *patterns[] = {
        "a.*b.*c",
        "(ab|cd|ef)+",
        "a.b.c.d.e",
        "(a|b)(c|d)(e|f)",
        "ab*c+d?ef",
        ".*hello.*world.*",
        "(abc|def|ghi|jkl)+",
        "a.*a.*a.*a",
    };
    int npatterns = 8;
    int nstrings = 100000;
    int total_matches = 0;

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    for (int p = 0; p < npatterns; p++) {
        compile_regex(patterns[p]);
        int matches = 0;
        for (int i = 0; i < nstrings; i++) {
            int len = 10 + (i % 50);
            gen_string(i + p * 1000, len);
            if (match_nfa(strbuf)) matches++;
        }
        total_matches += matches;
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    long ms = (t1.tv_sec - t0.tv_sec)*1000 + (t1.tv_nsec - t0.tv_nsec)/1000000;
    printf("matches: %d\n", total_matches);
    printf("time: %ld ms\n", ms);
    return 0;
}
