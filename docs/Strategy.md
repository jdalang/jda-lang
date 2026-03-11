Strategy

1. Top-level global recorder
Status: done

What changed:
- replaced the crashing direct top-level global metadata arrays with heap-backed pointer tables
- kept `jda0 -> jda1 -> hello.jda` working
- confirmed top-level `let` recording now completes during self-compile

Verified:
- const parsing completes
- struct parsing completes
- top-level `let` handling completes
- forward declarations are skipped correctly

2. Current blocker
Status: active

New bug:
- `jda1 -> jda1_sh2` now crashes in the first real function body, not in top-level scanning
- current trace reaches the first function body and dies during `live_compile_block(...)`
- last successful trace markers are effectively:
  - top-level scan done
  - first function selected
  - block created
  - `{` consumed
  - crash occurs while compiling the body

Likely cause:
- incomplete live field/array lowering for self-host code patterns such as:
  - `ct.cnt`
  - `ct.names_len[i]`
  - similar struct-backed table access in the first real function

3. Next fixes
Status: next

Work in order:
- make the first real function body compile without crashing
- focus on struct field load/address logic in the live compiler
- validate array indexing on struct fields
- validate globals flowing into local bindings with correct struct types

4. Verification target
Status: pending

Required command:
```sh
./jda1_sh2 ../../examples/hello.jda hello_sh2 && ./hello_sh2
```

Expected output:
```text
Hello Bare Metal
```
