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

**Not clear.** Seven are fixed; **1.8 and 1.9 are open** — a seventh function argument
is silently miscompiled, which is what caused 3.1. 1.7 was found while investigating
3.1, which remains open and is a different bug. Note how the last two were found:
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


### 1.7 A struct field used directly in a comparison compared the address ✅

**Status: FIXED.**

```jda
struct T { a: i64 b: i64 }
let t = T{ a: 5, b: 9 }
print("{t.a}")        // 5    always was correct
let s = t.a + 1       // 6    always was correct
if t.a == 5 { }       // took the ELSE branch
```

Struct types are carried as `sid + 1000`. The **live** postfix path passed that
value straight to `lookup_field_idx_flat`, which matches `g_field_owner` — a
bare sid. The lookup never matched, the access fell through to returning the
struct's base pointer, and the comparison compared an address:

```
149: 48 81 f9 05 00 00 00    cmp rcx,0x5     ; rcx is the struct base
```

The other copy of this path already normalised correctly (the
`lookup_field_idx_any` site); the live copy handled only the negative
struct-array encoding and not the `+ 1000` one.

Why it stayed hidden: printing a field and using it in arithmetic were always
correct, because `let` compiles its right-hand side through
`codegen_expr_inline` while `if` goes through `live_codegen_expr_inline`. Only
the `if` path was affected — so `let c = t.a == 5` gave the right answer while
`if t.a == 5` did not, which is a difference almost nobody would think to test.

This one drove **control flow**, so it silently took the wrong branch rather
than producing one wrong value. Anything shaped like `if node.kind == X` was
affected.

Covered by `tests/conformance/stage1/pass/struct_field_compare.jda`, which fails
on the previous compiler.

### 1.8 A seventh function argument is silently miscompiled ✅

**Status: FIXED.** This is what caused 3.1.

```jda
fn seven(a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64) -> i64 { ret g }

fn stress() -> i64 {
    let v0 = 10   let v1 = 11   let v2 = 12
    let v3 = 13   let v4 = 14   let v5 = 15
    let r1 = seven(v0, v1, v2, v3, v4, v5, 77)   // returned 13, the value of v3
    let r2 = seven(v5, v4, v3, v2, v1, v0, 88)   // returned 11, the value of v1
    ret r1 * 1000 + r2 + v0 + v1 + v2 + v3 + v4 + v5   // 13086, not 77163
}
```

**The diagnosis recorded here before was wrong.** It said the cause was a gap in
the DCE liveness marking, and that a naive fix produced a compiler that hung on
every input. Neither held up. `lower_fn_mark_uses_instr` — the register
allocator's own liveness — already handled the 7th argument, and the hang was
not caused by the marking at all. Three separate bugs were in play.

**(a) The argument was thrown away during parsing.** `codegen_call_inline`
stored only six arguments and, on seeing a seventh, skipped the remaining tokens
and clamped `arg_cnt` back to 6:

```
        arg_cnt = arg_cnt + 1
        if arg_cnt > 6 {
            // Recovery: skip malformed extra args until call close.
            ...
            arg_cnt = 6
        }
```

So the call was emitted as a six-argument call. `operand3` never reached 7,
`lower_call_push_arg7` never fired, and the callee read whatever was above the
return address. The whole binary contained zero `add rsp, 8` — the arg7 cleanup
— which is what made this visible: the path was dead, not merely mis-scheduled.
The sibling path `live_codegen_call_inline` had carried the 7th argument in
`itype` all along, so the two call paths disagreed.

**(b) The stack slot was released after the register pool was restored.**
`lower_call_cleanup_arg7` ran after `lower_instr_call_emit`, but that function
emits the pool restore itself. The nine restore pops therefore ran while the
argument slot was still on the stack, so every saved register came back holding
its neighbour's value and the caller's last live local was lost:

```
    call
    mov  %rax,%r12
    pop  %r11        <-- reads the pushed 7th argument
    ...
    pop  %rax        <-- reads one slot past the saved pool
    add  $0x8,%rsp   <-- far too late
```

That is why a call with live values around it came back holding one of the
caller's locals, and a call with nothing live happened to work. The cleanup now
runs between the result capture and the pool restore.

**(c) DCE did have a gap, and it did matter — but only once (a) was fixed.**
With the argument being passed, the constant feeding it was still collected,
because the DCE marking stopped at six. Adding the marking is what turned the
remaining wrong answers into right ones.

**Why the earlier "naive fix hangs" was a red herring.** It does hang, but for
a reason that has nothing to do with this bug: the naive fix added an `if`, and
`dce()` sat at exactly 256 basic blocks, the maximum a function may hold. The
257th block silently aliased block 255, and the resulting branch looped forever.
That is 1.12, now fixed and a hard error — so the marking here could have been
written inline after all. It stays in `dce_mark_call_arg7`, beside the existing
`dce_mark_syscall_extra`, because that is where it reads best; the 7th argument
still travels in a global for the parameter budget, not for block pressure.

Tests: `tests/conformance/stage1/pass/call_seven_args.jda` covers the bare call,
the pressured call, a 7-argument call nested as another's 7th argument, and
reads every caller local after the call. `tests/rejected/call_eight_args.jda`
pins the `JDA-C001` rejection at eight.

**Still open, same shape, different path.** Indirect calls (`OP_CALL_IND`, which
is what `call_closure` lowers to) cap out at five real arguments, and
`codegen_call_closure_inline` parses further arguments without storing them
while still counting them. Worse, the lowering pops into `RDI, RSI, RDX, R8, R9`
— **skipping RCX** — so the fourth argument lands in the fifth register:

```jda
let f4 = fn(a: i64, b: i64, c: i64, d: i64) -> i64 { ret n + a + b + c + d }
call_closure(f4, 1, 2, 3, 4)    // 106, not 110 -- d is lost
```

Recorded here rather than fixed, because it is a different lowering path.

### 1.12 A function past 256 basic blocks silently aliased block 255 ✅

**Status: FIXED — now a hard error, `JDA-C007`.**

The symptom recorded here was "one more local in a large function produces a
compiler that hangs". That was the wrong variable. It is not locals, and it is
not register pressure: it is **basic blocks**, and the number is 256.

`JirFunction` stores its blocks inline, so a function may hold at most 256.
`create_block_live` — the path the live codegen actually uses — handled the
overflow like this:

```
    let ok = id < 256
    let out_id = ok * id + (ok == 0) * 255
```

Past the cap it returned **block 255, a block already in use**, and said
nothing. An `if` whose then-block and end-block both came back as 255 produced a
branch with two identical targets, and the loop's back-edge landed inside its
own body:

```
    cmp    $0x0,%rax
    jne    0x8b601        <-- the body
    nopl   0x0(%rax,%rax,1)
    ...                   <-- the body, also reached by falling through
    jmp    0x8b601        <-- back to the body, forever
    add    $0x1,%rdx      <-- the loop increment, unreachable
```

The compiled program spun with no diagnostic anywhere.

**Why it looked like locals.** Both triggers observed while fixing 1.8 added an
`if`, not a local: the "naive fix" was `if o3 >= 7 { used[itype] = 1 }`. And two
of the compiler's own functions — `dce` and `codegen_call_inline` — sat at
**exactly 256 blocks**, right on the cap. One more `if` in either aliased a
block. Moving the work into a helper function fixed it because a helper gets its
own block budget, not because it relieved pressure.

That the compiler happened to sit exactly on a silent cliff, in the two
functions most likely to be edited, is why this cost so much: every edit to
either looked like it had broken something unrelated.

**The fix.** Overflow is a hard error. Aliasing a block is always a miscompile
and there is no correct code to fall back on, so there is nothing to recover to:

```
JDA-C007: function too complex: more than 256 basic blocks
```

Raising the limit is not a cheap alternative — `BasicBlock` holds `Instr[2048]`,
so the 256 blocks already cost tens of megabytes per function.

**Headroom.** Three functions were split so the compiler is not one edit from
failing to build: `dce_mark_instr` out of `dce`, `cg_conc_bi` out of
`codegen_call_inline`, and `lex_global_operators` out of `lex_global_fast`
(which had quietly become the tightest at 250). Peak block counts when the
compiler compiles itself, highest first:

| blocks | function |
|---:|---|
| 241 | `dce_mark_instr` |
| 214 | `try_small_print_program_fast` |
| 211 | `live_compile_let_stmt` |
| 205 | `main`, `codegen_call_inline` |
| 193 | `live_compile_block` |

Nothing is at the cap any more, but `dce_mark_instr` is the next one to split if
it grows. Test: `tests/rejected/block_limit.jda`.

**Note on 1.11.** This was recorded as "almost certainly the same underlying
defect as 1.11". It is not — 1.11 is a real register-allocation problem around
`IDIV`, and it remains open.

### 1.13 Global initialisers are ignored; a global read before its declaration is 0

**Status: OPEN — reproduced, not fixed.**

Two related name-resolution defects, both silent.

**Initialisers never run.** Every global starts at zero regardless of what it is
declared with:

```jda
let g_a = -1
let g_b = 7

fn main() {
    print("{g_a}\n")    // 0, not -1
    print("{g_b}\n")    // 0, not 7
}
```

The compiler's own source declares about a dozen globals as `-1`
(`g_iter_exit_bb`, `g_promo_slot0`, ...). They are all actually 0 at startup,
and the code works only because each is assigned before it is read.

**A global declared after its use resolves to 0.** Not to the global — to the
constant zero, with no diagnostic:

```jda
fn reader() -> i64 { ret g_late }
fn writer(v: i64) { g_late = v }

let g_late = -1

fn main() {
    writer(42)
    print("{reader()}\n")   // 0
}
```

The write lands on the real global; only reads that textually precede the
declaration are wrong, so the two halves of a program disagree about what the
name means. This cost an hour during 1.8: the fix looked correct and produced
`itype = 0` until the declaration was moved above its first use.

Reads of an undeclared name should be an error. Until they are, **declare
globals at the top of the file**, with the others.

### 1.9 An unknown character silently truncates the function

**Status: OPEN.**

```jda
fn main() {
    print("before ")
    let x = 6 $ 3      // any byte the lexer does not know
    print("after\n")   // never runs, no diagnostic, exit 0
}
```

`char_to_tok` returns `TOK_EOF` for a character it does not recognise, and the
statement loop treats EOF as end of input — so everything after a stray byte is
dropped. The program compiles, runs, exits 0, and simply stops producing output.

This is how **`^` hid**: it was never lexed (see the `bitwise_xor` test), so
every function using XOR was silently cut short at the first `^`. That is why
`stdlib/crypto.jda` could not compile and why a program doing `let z = x ^ y`
printed nothing after that line.

`^` is fixed. The general case is not: any other unexpected byte still truncates.

**A naive fix does not work.** Making `char_to_tok` report an error takes the
whole suite from 431 passing to 0 — `char_to_tok` is called speculatively from
several lexer paths that legitimately pass characters it does not map, so the
error has to go at the emit sites that mean "this really is a token", not in the
shared classifier. Reverted; not committed.

### 1.10 Integer literals in [0xE9000000, 0xE9FFFFFF] were rewritten into a NOP ✅

**Status: FIXED.**

Any integer literal whose value fell in `3909091328 .. 3925868543` came out
wrong, always by the same offset `0x441E26000000`:

```
fn main() {
    print("{3921009573}\n")     // printed 74900198251429
}
```

The value is materialised as `movabs rax, imm64`, so `3921009573` is encoded as
the bytes `A5 DB B5 E9 00 00 00 00`. A post-fixup pass, `nop_fallthrough_jmps`,
scanned each emitted function byte by byte for `E9 00 00 00 00` — a `JMP rel32`
whose displacement is zero, which merely falls through to the next instruction —
and replaced it with the five-byte NOP `0F 1F 44 00 00`. With no instruction
boundaries to work from, it matched the tail of that immediate and rewrote it,
turning the constant into `0x441F0FB5DBA5`.

The range is exactly the values whose most significant byte is `0xE9`, which is
why it looked arbitrary: `0xE9000000` and `0xE9FFFFFF` are both corrupted,
`0xE8FFFFFF` and `0xEA000000` are both fine, and `0xE9` sitting in any other
byte position is harmless.

The fix drops the byte scan. The fixup table already records the offset of every
jump displacement the lowerer emitted, so the NOP rewrite now happens inside
`lower_fn_patch_fixups`, keyed off a real jump site and applied only when the
computed displacement is zero. Regression test:
`tests/conformance/stage1/pass/literal_jmp_opcode_range.jda`.

This one had teeth. `sha_k(3)` in a SHA-256 implementation returns
`0xE9B5DBA5`, so the hash was silently wrong, and none of the 431 conformance
tests happened to use a literal in that window.

### 1.11 Division miscompiles: `x / (1 << n)`, and inline IDIV corrupts a pointer

**Status: OPEN — reproduced, worked around in `tools/pkg.jda`, not fixed.**

Two related failures, both around `IDIV`. `IDIV` reads and writes `RDX:RAX`, and
the register allocator does not appear to model that fully.

**(a) A shift as the divisor.** The divisor is computed as anything but a plain
constant and the result is wrong:

```
fn a(m: i64, n: i64) -> i64 { ret m / (1 << n) }
fn d(m: i64) -> i64 { ret m / (1 << 6) }
fn c(m: i64) -> i64 { ret m / 64 }

a(640, 6)   // 0    -- want 10
d(640)      // 0    -- want 10
c(640)      // 10   -- correct
```

`m + (1 << n)` is fine, so the shift itself is not the problem. Hoisting the
divisor into a local sometimes helps and sometimes produces a different wrong
answer, which is what makes it look like allocation rather than lowering.

**(b) Several inline divisions in a loop that also stores through a pointer
parameter.** This segfaults:

```
fn emit(h: &i64, out: &i8) {
    let i = 0
    loop i < 8 {
        let v = h[i]
        poke_byte(out, i * 4, (v / 16777216) % 256)
        poke_byte(out, i * 4 + 1, (v / 65536) % 256)
        poke_byte(out, i * 4 + 2, (v / 256) % 256)
        poke_byte(out, i * 4 + 3, v % 256)
        i = i + 1
    }
}
```

Reducing it to a single `poke_byte` per iteration, or moving each division into
its own one-line function, makes it work — the pointer survives when the divide
is not live across the store.

**Workarounds in use.** `tools/pkg.jda` computes powers of two with a `pow2`
helper instead of `1 << n`, and routes every byte extraction through
`fn byte_of(v: i64, d: i64) -> i64 { ret (v / d) % 256 }`. Both are noted at
their use sites.

**Why it matters.** Nothing in the conformance suite divides by a computed
power of two, so this is invisible today, and it silently produced a wrong
SHA-256 rather than failing.

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

### 2.4 `tools/*.jda` do not compile ✅

**Status: FIXED.** Both files compile, run, and are gated in CI by
`tests/pkg-selftest.sh` and `tests/lsp-selftest.sh`.

They were written against a language that does not exist. Between them they
used `impl` blocks, `own`/`ref` qualifiers, `bool`, `match`, `Result`/`Option`
and their combinators, generics (`Vec<T>`), closures, slices (`s[a..b]`),
enum variant paths (`JsonValue::Null`), associated functions (`X::y()`), the
`?` operator, `for x in xs`, and multi-value return. None of that is
implemented, and the earlier plan here — add each feature, then compile the
files — was the wrong way round: it made two aspirational files the
specification for the language.

They were rewritten against the language as it is instead, keeping the feature
set rather than the syntax:

| | before | after | covered by |
|---|---|---|---|
| `tools/pkg.jda` | 5 blocking features | semver, all five version-requirement forms, manifest parsing, SHA-256, `list`/`add`/`remove` | `pkg selftest` |
| `tools/lsp.jda` | 6 blocking features | all nine LSP methods, framing, diagnostics, hover, completion, definition, symbols, formatting | `lsp selftest` plus a driven protocol session |

What replaced what: `Vec<T>` and `HashMap` became parallel global arrays with an
arena; `Result`/`Option` became sentinel returns (`-1` for absent) and, where a
span had to come back, a pair of globals; `match` became `if` ladders; slices
became `(base, offset, length)` argument triples; and the JSON value tree became
a flat node arena for reading (`stdlib/json.jda`, also rewritten) and direct
byte emission for writing.

Two things worth keeping in mind for anything written next:

- **The rewrites found compiler bugs the test corpus did not.** `pkg.jda`'s
  SHA-256 turned up 1.10 and both halves of 1.11. Real programs exercise
  combinations that a corpus of small conformance cases does not.
- **`;` comments were never the blocker.** `;` is a valid comment today. The
  rewrites use `//` throughout because the rest of the tree does, not because
  they had to.

The bash tools they duplicate (`tools/jda-lsp.sh`, `tools/jda-pkg.sh`) are
untouched and still what the README's `jda pkg` and `jda-lsp` claims rest on.
Switching those entry points over to the compiled versions is a separate change.

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

### 3.1 Native x86-64 produced wrong code ✅

**Status: FIXED.** 431/431 on the runner, from 321/110.

110 of 430 conformance tests failed on a stock x86-64 runner while all passed
under `linux/amd64` emulation. The cause recorded here for months — programs
that allocate producing no output — was wrong, and it pointed every earlier
investigation at the runtime rather than the compiler.

**Root cause: a seventh function argument is miscompiled (see 1.8).** All eight
SIB load/store emitters took seven parameters with the displacement last, so the
displacement never arrived and the callee read whatever was on the stack at that
slot. It now travels in `g_sib_disp` with six-parameter emitters. Stores set
zero, which is correct by construction; loads set `ins.imm`, a real displacement
that was equally being lost — so indexed loads with an offset were reading from
the wrong address too.

That single defect accounts for every observation:

- **The platform split.** Stale stack is 0 under emulation, where the address
  space is fixed, so the compiler looked correct *and* deterministic there.
- **The nondeterminism.** On the runner the stale value was 514 or 518
  depending on the run, because stack contents vary with ASLR.
- **Why disabling ASLR made it stable but not correct.** A fixed layout gives
  fixed garbage, not right answers.
- **Why two earlier fixes changed nothing.** Zeroing `imm` at the fusion, then
  reading a literal zero in the lowering, both set a value that was discarded
  before the emitter saw it.

Found by testing the assumption underneath every hypothesis — that both machines
run the same bytes. The compiler binary hashed identically while the binary it
*produced* did not; block-hashing narrowed that to 1 of 257 4KB blocks and a byte
diff to two bytes, the low half of a `disp32`. Disabling ASLR made the target
hold still, which is what finally made the diff meaningful.

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
6. ~~**2.4 / 2.5**~~ — **done**. 2.5 archived; 2.4 fixed, but not the way this
   list proposed. Adding tuple destructuring, then enum paths, then combinators
   would have meant letting two aspirational files dictate the language. Both
   were rewritten against the language as it is instead, keeping every feature,
   and each now carries a selftest gated in CI.
7. **3.2** — CI assertion on the global count.
8. ~~**3.1**~~ — **done**, and it was a compiler bug rather than a platform one:
   a fused store took its displacement from an uninitialised field.
9. ~~**1.8**~~ — **done**, and the diagnosis recorded for it was wrong: the
   7th argument was discarded during parsing, and the stack slot was released
   after the register pool had been restored. DCE was a third, smaller part.
10. ~~**1.12**~~ — **done**, and it was basic blocks, not locals: a function
   past 256 blocks silently aliased block 255, and the compiler's two most-edited
   functions sat exactly on that cap. Now `JDA-C007`. Unrelated to **1.11**,
   which stays open and is now the widest-reaching Tier 1 item.
11. **1.13** — globals ignore their initialisers, and a global read above its
   declaration resolves to 0 with no diagnostic. Cheap to detect, and it makes
   otherwise-correct fixes look wrong.
12. **1.9** — diagnosed; the naive fix takes the suite from 431 passing to 0.

## A note on the README

The README currently leads with "33x faster compilation than Rust", "Beats C on
2 of 4 benchmarks", "136 stdlib packages" and "ML primitives — tensors, autograd,
neural networks". Both ML examples are in the table above.

The gap between those claims and Tier 1 is the real adoption problem. A visitor
who clones this and writes `let xs = [1, 2, 3]` gets a segfault, and every
headline number becomes suspect at once. Fix Tier 1 and Tier 2 before doing
anything to attract traffic — the first impression is only available once.
