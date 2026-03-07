 jda0 (NASM assembler) — ALL 23 bugs DONE ✅ — handles structs, arrays, pointers, else-if, and/or, multi-function, etc. 
  It
  successfully compiles jda1.jda into a working binary.
  March 4, 2026 update: fixed stage-0 pass-count corruption (`P2 0`/549-byte output) in `bootstrap/stage0/jda0.asm`.

  jda1 (self-hosted compiler) — can compile simple programs but is missing 10 features needed to compile itself:

  ┌────────────────┬──────┬────────────────┐
  │ Feature        │ jda0 │ jda1           │
  ├────────────────┼──────┼────────────────┤
  │ Multi-function │ ✅   │ ✅             │
  ├────────────────┼──────┼────────────────┤
  │ Structs        │ ✅   │ ✅             │
  ├────────────────┼──────┼────────────────┤
  │ Arrays         │ ✅   │ ❌             │
  ├────────────────┼──────┼────────────────┤
  │ Pointers/refs  │ ✅   │ ❌             │
  ├────────────────┼──────┼────────────────┤
  │ String escapes │ ✅   │ ⚠️ Partial     │
  ├────────────────┼──────┼────────────────┤
  │ print(int)     │ ✅   │ ❌             │
  ├────────────────┼──────┼────────────────┤
  │ else-if        │ ✅   │ ❌             │
  ├────────────────┼──────┼────────────────┤
  │ const decls    │ ✅   │ ❌             │
  ├────────────────┼──────┼────────────────┤
  │ and/or/>=/<=   │ ✅   │ ❌             │
  ├────────────────┼──────┼────────────────┤
  │ asm blocks     │ ✅   │ ❌             │
  ├────────────────┼──────┼────────────────┤
  │ 5+ args        │ ✅   │ ❌             │
  └────────────────┴──────┴────────────────┘

  Phase 1 is about closing this gap so jda1 can compile jda1.jda → true self-hosting.

  String escapes (Issue #5): Lexer handles `\"` to prevent premature string termination.
  Escape sequence conversion (\n, \t, \\, \") blocked by jda0 if-statement bug in emit_strlit.
  Branch: `issue-5-string-escape-sequences` — requires jda0 compiler fix to complete.
