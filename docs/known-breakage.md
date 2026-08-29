# Known breakage

What is actually broken in Jda today, in the order it needs fixing.

Every item here was reproduced against the committed `bootstrap/stage0/jda1`
under `linux/amd64` emulation on 2026-08-29. Each one lists the exact input and
what the toolchain did with it. Nothing in this file is inferred from reading
the source; if it says "segfaults", it segfaulted.

Reproduce any of it with:

```bash
docker build --platform=linux/amd64 -t jda-build -f docker/Dockerfile .
docker run --rm --platform=linux/amd64 -v $(pwd):/jda -w /jda jda-build \
  bash -lc 'ulimit -s unlimited; bootstrap/stage0/jda1 <file> /tmp/out && /tmp/out'
```

---

## Tier 1 — the compiler is silently wrong

These matter more than everything below combined. The compiler accepts the
program, emits a binary, and the binary is wrong. Nothing reports anything, so
neither a person nor a model writing Jda has any signal that the code is bad.
A language that wants to be written by an LLM cannot have these.

### 1.1 Local array declarations compile clean and segfault

**Status: open. No lowering exists for this at all.**

```jda
fn main() {
    let nums = [3, 1, 2]
    print("{nums[0]}\n")     // segfault
}
```

```jda
fn main() {
    let buf = [8]i64
    buf[0] = 42
    print("{buf[0]}\n")      // segfault
}
```

Both forms parse, compile with **no diagnostic**, exit 0 from the compiler, and
then crash at run time. There is no array-literal or local-array lowering in the
compiler; the syntax falls through the expression parser and the resulting code
is garbage. Array *fields* inside a struct (`data: i64[256]`) are a separate
path and do work.

This is the single most damaging item in the file. It is the first thing a
newcomer writes, it is used in **32 places across 6 stdlib files**, and it is
the one construct where the toolchain stays silent and wrong.

Two ways out, in order of preference:

1. Implement local arrays properly.
2. Until then, **reject them** with a `JDA-F0xx` code. Rejecting breaks the 32
   stdlib sites and `examples/mlp.jda` / `examples/transformer.jda`, which is
   precisely why it has not been done yet — but those files do not work today
   either. Failing loudly is strictly better than emitting a crashing binary.

Recorded in `docs/llm-context.md` so models stop generating it.

### 1.2 Tuple destructuring binds nothing

**Status: open.**

```jda
fn f() -> i64 { ret 7 }
fn main() {
    let (a, b) = f()
    print("{a}\n")       // error: unknown variable in string interpolation
}
```

`let (a, b) = ...` is accepted and discarded — the names are never bound. The
statement itself produces no diagnostic; you only find out when you use one of
the variables, and only then if you use it somewhere that happens to check.
`examples/mlp.jda:28` is a four-element version of this.

Either implement it or reject the `let (` form outright.

### 1.3 Unknown methods evaluated to the receiver

**Status: FIXED on `compiler/reject-unknown-methods-json-contract` (`JDA-C005`).**

```jda
let n = 42
let s = n.to_string()    // used to compile, run, and print 0
```

A call-shaped access resolving to no field, no impl method and no primitive
method fell through as the receiver. `check --json` reported `ok:true`. This is
the exact shape a hallucinated API takes. Now a hard error.

Kept here as the reference case for what Tier 1 means.

---

## Tier 2 — the shipped surface does not work

Anyone who clones the repo hits these before anything else.

### 2.1 Half the examples do not compile

4 of 8 fail. Two of them are the ML showcase the README's headline claims rest on.

| File | Fails with | Cause |
|---|---|---|
| `examples/mlp.jda:28` | `expected 'identifier'` | tuple destructuring (1.2) |
| `examples/transformer.jda:34` | `expected 'integer literal'` | `const D_HEAD = D_MODEL / N_HEADS` — see 2.3 |
| `examples/web_server.jda:25` | `expected 'integer literal'` | `const LISTEN_ADDR = "0.0.0.0"` — see 2.3 |
| `examples/stdlib_demo.jda` | `undefined function: fmt_i64` | see 2.2 |

Working: `hello.jda`, `multi_fn.jda`, `test_hello.jda`, `test_if.jda`.

Worth noting what that leaves. `test_hello.jda` and `test_if.jda` are trivial
smoke files, so the repo ships exactly **two** examples that both work and
demonstrate anything — `hello.jda` and `multi_fn.jda`. Every example that shows
Jda doing something a person would actually want to do is in the broken table
above.

### 2.2 `fmt_i64` is defined in stdlib but not reachable

`examples/stdlib_demo.jda` fails on `undefined function: fmt_i64`, yet the
function exists in **both** `stdlib/fmt.jda:17` and `stdlib/prelude.jda:22`.
Something in the import/link path does not pick it up. Worth understanding
before trusting the "136 stdlib packages" claim — that number is only meaningful
if the packages are reachable from a user program.

### 2.3 `const` accepts only bare integer literals

**Status: open.** Not a miscompile — it fails loudly — but it is a sharp,
undocumented edge that breaks real files.

```jda
const A = "hi"        // error: expected 'integer literal'
const M = 64
const N = 4
const D = M / N       // error: expected 'integer literal'
const B = 32 / 2      // OK — literal arithmetic folds fine
```

So: arithmetic on **literals** works; arithmetic on **other constants** does
not, and **string constants** do not exist. This breaks `web_server.jda`,
`transformer.jda` and `tools/pkg.jda`.

### 2.4 `tools/*.jda` do not compile

- `tools/pkg.jda:41` — `const REGISTRY_HOST = "pkg.jdalang.org"` (2.3)
- `tools/lsp.jda:35` — uses `;` as a line comment; Jda's comment is `//`

Neither is built or tested by CI. Either fix them, or move them out of the repo
root so a visitor does not read them as working code.

### 2.5 `bootstrap/stage1/jda1-mac.jda` is unbuilt and drifting

Nothing in the repo builds or tests it. It still carries defects since fixed in
`jda1.jda` (the uncompensated token accessors), and does not have the diagnostic
or `JDA-C005` fixes. Every commit widens the gap. Wire it into CI or delete it.

---

## Tier 3 — infrastructure that hid the above

### 3.1 Native x86-64 self-host produces a broken compiler

`jda1-bootstrap` run natively yields a `jda1` that does not work on any input.
CI records it as a hang — "build succeeds, the resulting compiler then times
out" (`.github/workflows/ci.yml:16-19`); it has also been reported as a segfault
on `examples/hello.jda`. The same bootstrap under `linux/amd64` emulation
produces a working compiler, which is the documented workaround.
This is the first thing a Linux contributor hits, and the workaround means the
native path is never exercised.

### 3.2 The pinned bootstrap seed nearly stopped building the compiler

**Status: FIXED (merged in #16).**

`bootstrap/bin/jda1-bootstrap` enforces a 256-global cap from before this source
raised its own cap to 2048. One added global took `jda1.jda` to 257 and the seed
could no longer build it — which broke the benchmark job **and `release.yml`**,
so no release could be produced for three commits. The Test job stayed green
because it had been switched to the committed binary, which hid it.

Fixed by removing 19 dead globals (237 now). **The headroom is 19 globals.** The
next few additions will hit this again. Decide deliberately whether to refresh
the seed or hold `jda1.jda` under the cap, and add a CI assertion on the count
so it fails on the change that causes it rather than three commits later.

### 3.3 `--json` only worked on one of three fatal paths

**Status: FIXED on `compiler/reject-unknown-methods-json-contract`.**

`check --json` was advertised as machine-readable, but only `report_error_at`
honoured it. Undefined functions and all 37 `panic()` sites printed prose, so a
client parsing the stream got a bare line instead of an object. Now `JDA-C006`
and `JDA-X001`. `tests/diagnostics-test.sh` sweeps every `tests/rejected/` case;
its two original fixtures both went through the one path that already worked,
which is why this was never caught.

---

## Suggested order

1. **1.1 local arrays** — implement or reject. Nothing else in this file matters
   as much, and it blocks 2.1.
2. **1.2 tuple destructuring** — implement or reject.
3. **2.3 `const`**, then **2.2 `fmt_i64`** — together these unblock three of the
   four broken examples.
4. **2.1** — get all shipped examples compiling and running in CI, so this class
   of breakage cannot return.
5. **2.4 / 2.5** — fix or remove the non-compiling files.
6. **3.2** — CI assertion on the global count.
7. **3.1** — native self-host.

## A note on the README

The README currently leads with "33x faster compilation than Rust", "Beats C on
2 of 4 benchmarks", "136 stdlib packages" and "ML primitives — tensors, autograd,
neural networks". Both ML examples are in the table above.

The gap between those claims and Tier 1 is the real adoption problem. A visitor
who clones this and writes `let xs = [1, 2, 3]` gets a segfault, and every
headline number becomes suspect at once. Fix Tier 1 and Tier 2 before doing
anything to attract traffic — the first impression is only available once.
