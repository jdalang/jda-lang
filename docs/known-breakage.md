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

**Clear as of 2026-08-29** — all six fixed. Note how the last two were found:
not by reading source, but by running programs and checking *values*. 1.4 hid
behind a clean compile, and 1.5 was actively protected by five passing tests
that had recorded its wrong output. Only 1.6 announced itself.

These matter more than everything below combined. The compiler accepts the
program, emits a binary, and the binary is wrong. Nothing reports anything, so
neither a person nor a model writing Jda has any signal that the code is bad.
A language that wants to be written by an LLM cannot have these.

### 1.1 Local array declarations compiled clean and segfaulted ✅

**Status: FIXED.** All three spellings allocate real memory and agree.

```jda
fn main() {
    let lit   = [3, 1, 2]     // literal
    let sized = [4]i64        // bracket-first
    let tf    = i64[2]        // type-first
}
```

The root cause was narrower than it looked. **`i64[N]` always worked** —
`codegen_arr_primary` allocated for it correctly. The two *bracket-first*
spellings had no lowering at all: they fell through the expression parser,
compiled with no diagnostic, and produced a binary that indexed into garbage
and crashed.

Those are exactly the spellings that `docs/llm-context.md`, six stdlib files
and every newcomer actually write, so the one working form was the one nobody
used.

`codegen_bracket_array` now handles both. `[N]T` allocates `N * sizeof(T)`,
honouring narrow element types; `[a, b, c]` counts its elements, allocates, and
stores each one, with full expressions allowed as elements. A sized form whose
length is not an integer literal is rejected with `JDA-F007` rather than being
silently misread as a one-element literal.

Covered by `tests/conformance/stage1/pass/local_arrays.jda`, which segfaults on
the previous compiler.


### 1.2 Tuple destructuring bound nothing ✅

**Status: FIXED — rejected, not implemented (`JDA-F008`).**

```jda
let (a, b) = f()     // now: error: tuple destructuring is not supported
```

The let handler reads a single identifier for the name, so the `(` was taken as
the name and the elements were never bound. The statement compiled, emitted no
diagnostic, and the variables simply did not exist — you found out at the first
use, and only where that use happened to be checked.

Rejected rather than implemented because there is nothing to destructure: the
language has no tuple type and `OP_RET` carries one operand. A function
returning several values returns a **struct** and the caller reads its fields,
which is what `stdlib/process.jda` already does (`-> WaitResult`, `-> ProcInfo`).
Implementing the syntax would mean inventing both a tuple type and a
multi-value calling convention — a real feature, not a bug fix, and one that
should be decided on its own merits rather than smuggled in under this item.

Covered by `tests/rejected/tuple_destructuring`.


### 1.3 Unknown methods evaluated to the receiver ✅

**Status: FIXED (`JDA-C005`, merged in #18).**

```jda
let n = 42
let s = n.to_string()    // used to compile, run, and print 0
```

A call-shaped access resolving to no field, no impl method and no primitive
method fell through as the receiver. `check --json` reported `ok:true`. This is
the exact shape a hallucinated API takes. Now a hard error.

Kept here as the reference case for what Tier 1 means.

### 1.4 `const` expressions were silently truncated ✅

**Status: FIXED.**

```jda
const B = 32 / 2      // bound 32, not 16
const C = 10 + 5      // bound 10, not 15
```

`parse_const_decl` read one integer literal and stopped, leaving the rest of the
expression in the token stream for the top-level scanner to skip. No diagnostic,
wrong binary. A constant could not refer to another constant at all.

This was recorded in 2.3 as a *loud* failure ("`const` accepts only bare integer
literals"), which was wrong: it failed loudly for strings, and silently produced
a wrong number for arithmetic. It was found by checking a value, not by checking
that something compiled — the earlier note here that `const B = 32 / 2` "works"
came from watching it compile.

`const_expr_add`/`_mul`/`_primary` now fold literals, declared constants, unary
minus, parentheses and `+ - * / %` with the usual precedence, and reject
anything else with `JDA-P013` rather than truncating. String constants are
supported. A constant whose value is genuinely `-1` also resolves now; the three
codegen sites tested `lookup_const(...) != -1`, so `-1` doubled as "not a
constant".

Covered by `tests/conformance/stage1/pass/const_expressions.jda`.

### 1.5 Negative integers printed as unsigned ✅

**Status: FIXED.**

```jda
let x = 0 - 7
print("{x}\n")      // 18446744073709551609
```

The value was correct — arithmetic on it worked — but `print` rendered an `i64`
as unsigned, so every negative number came out as a 20-digit number. The program
compiled, ran, exited 0, and printed something false.

`lower_print_i64` emits the digit loop as machine code, and that loop divides
with `DIV`, which is unsigned; nothing checked the sign. It now negates into the
magnitude before the loop and prepends `-` afterwards, re-testing `r12`, which
still holds the original — so no register has to be reserved across the loop.
`INT64_MIN` needs no special case: negating it leaves the same bit pattern,
which `DIV` reads as 9223372036854775808, and the sign makes that correct.

**Five conformance expectations had encoded the bug.** `compress_basic`,
`mmap_basic`, `netrc_basic`, `sched_basic` and `socketserver_basic` all assert
on a `-1` sentinel returned by a stdlib "not found" or stub path, and their
`.expected` files recorded `18446744073709551615`. Those five are corrected.
`i128_basic` contains a similar-looking literal and was **left alone** — its
value is 2^64+1, a genuine 128-bit result, not a sentinel.

That is worth noting on its own: a passing suite had been pinning wrong output
in five places, so the bug was not merely unnoticed, it was protected.

Covered by `tests/conformance/stage1/pass/negative_print.jda`.

### 1.6 String interpolation did not resolve constants ✅

**Status: FIXED.**

```jda
const PORT = 8080
print("{PORT}\n")     // error: unknown variable in string interpolation
```

Interpolation resolved locals, then globals, then reported an error —
constants were missing from the chain entirely, so a constant had to be copied
into a `let` first, in the most common way to print anything.

Constants now resolve after globals. A **string** constant is written like a
literal segment; only an integer one goes through `PRINT_INT`. Locals still
shadow a constant of the same name, an unknown bare name is still `JDA-R002`,
and `"{a + 4}"` still compiles as an expression.

Covered by `tests/conformance/stage1/pass/interp_constants.jda`.

---

---

## Tier 2 — the shipped surface does not work

Anyone who clones the repo hits these before anything else.

### 2.1 Half the examples did not compile ✅

**Status: FIXED**, and now enforced.

Four of eight had stopped compiling, including the two the README's ML claims
rest on. `tests/examples-test.sh` compiles **and runs** every file in `examples/`,
diffing against a recorded `.expected`. An example with no `.expected` fails
too, so one cannot be added without coverage.

CI runs it as two steps, **both gating**: `--compile-only` first, since
compilation is what actually regressed, then run-and-compare.

The run step was briefly made non-gating on the theory that `stdlib_demo`'s
`alloc_pages` calls would hit the native failure in 3.1. The evidence says
otherwise — run 33257838481 passed both steps on that runner — so it gates. See
3.1, which is now known to be mis-diagnosed.

Per-example build flags live beside the file: `<name>.include` for a required
`--include`, and `<name>.sed` to normalise values that legitimately vary per run
(timestamps). Both are narrow by design.

Three of the four were never fixable. `mlp.jda`, `transformer.jda` and
`web_server.jda` are design sketches in a Rust-like dialect this language does
not implement — associated functions, turbofish generics, range loops, `&mut`,
`.unwrap_or_else(|e| ...)`. They are moved to `examples/aspirational/` with a
README stating plainly that they do not compile, rather than deleted, so nothing
is lost and no visitor reads them as working code.

The fourth, `stdlib_demo.jda`, was never broken at all — see 2.2.

### 2.2 `fmt_i64` is unreachable — **this was wrong**

**Status: NOT A BUG. Retracted.**

`stdlib_demo.jda` compiles and runs correctly:

```bash
jda build --include stdlib/prelude.jda examples/stdlib_demo.jda -o /tmp/sd && /tmp/sd
```

Its second line has always said exactly that. This entry existed because the
survey that produced this file compiled every example bare, without the
`--include` the file documents, and recorded the resulting `undefined function:
fmt_i64` as a defect.

Left in place rather than deleted, because it is the third claim in this file to
fail — after 1.1 and 1.2 each "blocking" an example they did not — and all three
failed the same way: by reasoning from one command's output instead of checking
what the program actually needed. The examples suite now runs it with its
documented flags on every push.

### 2.3 `const` accepts only bare integer literals ✅

**Status: FIXED — see 1.4, which is what this actually was.** The half of it
that broke real files was not the loud failure recorded here but a silent
truncation of any `const` containing arithmetic.

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

**Status: OPEN — being fixed.** `tools/lsp.jda` and `tools/pkg.jda` are
self-hosted rewrites of tools that already exist and work in bash
(`tools/jda-lsp.sh`, 944 lines; `tools/jda-pkg.sh`, 716 lines). The README's
`jda pkg` and `jda-lsp` claims rest on those bash implementations, so nothing
user-facing is blocked by this.

The `;` comments in both files are **not** a blocker — `;` is a valid comment
today; converting them to `//` is a separate cosmetic migration.

What actually blocks them is language surface that does not exist yet:

| Needed | `lsp.jda` | `pkg.jda` |
|---|---|---|
| Tuple destructuring | 3 sites | 3 sites, one 8-element |
| Option/Result combinators (`.unwrap_or`, `.map`) | **28 sites** | 1 site |
| Enum variant paths (`JsonValue::Null`) | yes | — |
| Associated functions (`X::y()`) | 2 sites | 11 sites |
| `?` on a destructuring `let` | — | yes |

This is a language roadmap, not a build fix, and is being done as a sequence of
PRs rather than one. Tuple destructuring comes first: it is the largest shared
blocker, and it replaces the `JDA-F008` rejection added under 1.2, which was
explicitly "until a tuple type exists".

### 2.5 `bootstrap/stage1/jda1-mac.jda` is unbuilt and drifting ✅

**Status: ARCHIVED**, at `bootstrap/stage1/unmaintained/jda1-mac.jda`.

Nothing built, tested or referenced it — `tools/jda-macos.sh` generates assembly
through a separate path and never touches it. It still carries the clamping
token accessors fixed in `jda1.jda`, and has none of the six Tier 1 fixes, so
every change to the compiler widened the gap silently.

Moved rather than deleted, with a README listing exactly what it is missing. To
revive it, port those fixes **and wire it into CI in the same commit**: a macOS
port that is not built is already broken, it just has not been told yet.

---

## Tier 3 — infrastructure that hid the above

### 3.1 Native x86-64 produced wrong code — `lea_fuse_store` left `imm` unset

**Status: FIXED (pending native confirmation).** This was never a platform bug.

110 of 430 conformance tests failed on a stock x86-64 runner while all passed
under `linux/amd64` emulation. The recorded cause — programs that allocate
producing no output — was wrong, and it sent every previous look at the runtime.

The actual cause is a **compiler** bug. `lea_fuse_store` rewrites
`STORE_MEM(val, addr)` into `STORE_MEM_SIB(val, base, idx, scale)` in place when
the address matches `base + (idx << k)`. It sets `op` and the four operands and
**never sets `imm`** — but `lower_store_mem_sib` emits `imm` as the `disp32` of
`mov [base + idx*scale + disp], val`. Nothing ever sets `imm` on a `STORE_MEM`,
and the plain lowering does not read it, so the field held whatever the slot
happened to contain.

That value is environment-dependent. On this machine it was 0 and every store
was correct; on the runner it was **518**, so `p[0] = x` wrote to `p + 518` and
the next read of `p[0]` returned 0 — no crash, no diagnostic, just a wrong
program. It explains all three observed signatures: wrong values where the
displaced write was never read back, segfaults where `p + garbage` left the
mapping, and empty output where a length or buffer pointer was the casualty. It
also explains why failures tracked program size: more stores fused, more chances
to hit a non-zero slot.

`lea_fuse_load` deliberately preserves `imm` and is correct — `LOAD_MEM` does
carry a real displacement (`ld.imm = imm_off * elem_sz_i`). Only the store side
is cleared.

How it was found, since the path matters more than the fix: the compiler binary
hashes identically on both machines, but the binary it *produces* did not
(`f064c959..` here, `273d42a6..` there) from identical source and identical
paths, while being deterministic across repeated local runs. Block hashing the
output narrowed it to one 4KB block out of 257, and a byte diff of that block to
**two bytes** — the low half of that `disp32`.

The fix is a no-op locally: the produced binary is byte-identical, because `imm`
was already 0 here. That is the point — the bug was only ever observable where
the uninitialised value was not 0.

### 3.2 The pinned bootstrap seed nearly stopped building the compiler ✅

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

### 3.3 `--json` only worked on one of three fatal paths ✅

**Status: FIXED (merged in #18).**

`check --json` was advertised as machine-readable, but only `report_error_at`
honoured it. Undefined functions and all 37 `panic()` sites printed prose, so a
client parsing the stream got a bare line instead of an object. Now `JDA-C006`
and `JDA-X001`. `tests/diagnostics-test.sh` sweeps every `tests/rejected/` case;
its two original fixtures both went through the one path that already worked,
which is why this was never caught.

---

## Suggested order

1. ~~**1.1 local arrays**~~ — **done**. Note that fixing it did *not* unblock
   2.1: all four broken examples fail on 1.2, 2.2 and 2.3 instead. The claim
   here that 1.1 blocked them was wrong — the table in 2.1 already attributed
   them correctly.
2. ~~**1.2 tuple destructuring**~~ — **done**, rejected with `JDA-F008`. As with
   1.1, the "blocks `examples/mlp.jda`" claim here was wrong: mlp is blocked by
   at least six unimplemented constructs, not by this one. This item also
   claimed Tier 1 was then clear; that held for about an hour, until 1.4 and 1.5
   turned up while working on 2.3.
3. ~~**2.3 `const`**~~ — **done**; it turned out to be 1.4, a silent truncation
   rather than the loud failure recorded here. Both examples it blocked moved on
   to their *next* error, exactly as this step warned: transformer to `JDA-F008`,
   web_server to `JDA-C005`. **2.2 `fmt_i64`** is next.
4. ~~**1.5 negative printing**~~ — **done**. Fixing it exposed five conformance
   expectations that had encoded the wrong output, which is the more useful
   finding: a green suite was protecting the bug.
5. ~~**2.1**~~ — **done**. `tests/examples-test.sh` gates every example in CI.
   Three unfixable sketches moved to `examples/aspirational/`; the fourth was
   never broken (2.2, retracted).
6. **2.4 / 2.5** — ~~2.5 archived~~. 2.4 is being *fixed* rather than removed:
   tuple destructuring first, then enum variant paths, then Option/Result
   combinators. Multi-PR language work.
7. **3.2** — CI assertion on the global count.
8. ~~**3.1**~~ — **done**, and it was a compiler bug rather than a platform one:
   a fused store took its displacement from an uninitialised field.

## A note on the README

The README currently leads with "33x faster compilation than Rust", "Beats C on
2 of 4 benchmarks", "136 stdlib packages" and "ML primitives — tensors, autograd,
neural networks". Both ML examples are in the table above.

The gap between those claims and Tier 1 is the real adoption problem. A visitor
who clones this and writes `let xs = [1, 2, 3]` gets a segfault, and every
headline number becomes suspect at once. Fix Tier 1 and Tier 2 before doing
anything to attract traffic — the first impression is only available once.
