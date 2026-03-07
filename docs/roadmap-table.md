 jda0 (NASM assembler) — ALL 23 bugs DONE ✅ — handles structs, arrays, pointers, else-if, and/or, multi-function, etc. 
  It
  successfully compiles jda1.jda into a working binary.

  jda1 (self-hosted compiler) — can compile simple programs but is missing 12 features needed to compile itself:

  ┌────────────────┬──────┬────────────────┐
  │ Feature        │ jda0 │ jda1           │
  ├────────────────┼──────┼────────────────┤
  │ Multi-function │ ✅   │ ❌ (only 1 fn) │
  ├────────────────┼──────┼────────────────┤
  │ Structs        │ ✅   │ ❌             │
  ├────────────────┼──────┼────────────────┤
  │ Arrays         │ ✅   │ ❌             │
  ├────────────────┼──────┼────────────────┤
  │ Pointers/refs  │ ✅   │ ❌             │
  ├────────────────┼──────┼────────────────┤
  │ String escapes │ ✅   │ ❌             │
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