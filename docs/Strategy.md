Strategy

1. Stage 0 bootstrap stability
Status: ✅ done

Done:
- moved large stage-0 buffers off `.bss` and onto `mmap`
- fixed the `gen_stmt` stack leak
- fixed `gen_fn` frame-size patch ordering
- fixed stage-0 pointer handling needed for selfhost bring-up

Verified:
- `jda0` builds and runs
- `jda0 -> jda1 -> hello.jda` works
- current hello output is `Hello Bare Metal`

2. Stage 1 selfhost progress
Status: partially done

Done:
- removed the earlier top-level global recorder crash
- added minimal top-level global tracking for stage 1
- extended `OP_CALL` handling from 3 args to 6 args
- replaced fragile const-table struct storage with flat global const arrays
- added early const sanity checking so startup const failures surface immediately
- fixed several expression/codegen blockers:
- postfix field/index handling now moves much further
- unary `-1` no longer crashes
- stage-1 call parsing no longer breaks obvious postfix arguments like `x[i]` and `obj.field`
- preserved struct element type across `[...]`, fixing forms like `toks[pos[0]].type`
- flattened several fragile nested call-argument forms in top-level parsing
- added fast paths for simple terminal expressions and simple comparisons

Verified:
- selfhost gets far past top-level scan
- selfhost gets well into real function-body compilation
- the earlier infinite loop at `expect(..., TOK_CONST)` is gone
- startup constant lookup now works
- selfhost gets through multiple helper calls and struct/array expressions that used to fail much earlier

3. Current bug
Status: active blocker

Current failure:
- `jda1 -> jda1_sh2` does not finish
- the current `TOK_CONST` loop is fixed
- the current blocker is later in top-level type parsing / selfhost codegen
- the latest narrowed failure was around simple expressions following:
  - `lookup_struct(stab, src, type_start, type_len)`
  - `if sid >= 0 { ... }`
- the failure has been moving forward by flattening nested index/field call arguments and by special-casing simple expressions

Meaning:
- the remaining bugs are no longer broad bootstrap issues
- the active class of bug is still fragile lowering of simple-but-nested source forms in stage 1
- especially:
  - indexed values used as locals
  - local struct field access used in later expressions
  - simple identifier comparisons that should bypass the full precedence path

4. Next fix
Status: next

Work in order:
- re-run Docker verification on the latest `sid >= 0` comparison fast-path patch
- map the next exact failing token window after that patch
- continue flattening fragile nested forms when they appear:
  - `toks[pos[0]]`
  - `local.field`
  - `arr[idx]`
  - field/index expressions passed directly as call arguments
- keep converting fragile complex RHS/call-arg shapes into explicit locals where needed

Concrete next edits:
- verify whether the new simple-comparison fast path clears `if sid >= 0`
- if not, patch that exact expression path directly
- if yes, map the next failure and flatten that source shape the same way
- after top-level type parsing stabilizes, continue into the next real selfhost function body blocker

Expected outcome of next fix:
- move selfhost materially past the current top-level parsing/type-resolution failure
- keep narrowing to one concrete expression shape at a time until `./jda1 ../stage1/jda1.jda jda1_sh2` completes

5. Final testing
Status: pending

Selfhost is complete only if both pass:

Step 1:
```sh
./jda1 ../stage1/jda1.jda jda1_sh2
```

Step 2:
```sh
./jda1_sh2 ../../examples/hello.jda hello_sh2 && ./hello_sh2
```

Expected output:
```text
Hello Bare Metal
```

Issue 10 should be marked done only after both steps pass in Docker/Linux without the debug loop or crash.
