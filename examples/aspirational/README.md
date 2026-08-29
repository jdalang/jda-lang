# Aspirational sketches — these do not compile

The three files here are **design sketches, not working programs.** None of them
compiles against the language as it exists, and none is close to it. They are
kept because they show intended direction, and moved out of `examples/` because
a visitor reasonably reads that directory as working code — the README's ML
claims rested on two of these.

Do not treat their compile errors as a bug list. Fixing the first error in each
just reveals the next; every one of them needs several unimplemented language
features, not a fix.

| File | Needs |
|---|---|
| `mlp.jda` | tuple destructuring, generic turbofish with associated functions (`Linear<2, 16>::new()`), named arguments (`Adam::new(lr: 0.01)`), range loops (`loop epoch in 0..1000`), `&mut` references, and `mse_loss_grad`, which does not exist anywhere in the tree |
| `transformer.jda` | tuple destructuring, range loops, associated functions (`MultiHeadAttention::new()`) |
| `web_server.jda` | associated functions (`TcpListener::bind(...)`), Rust-style combinators with closures (`.unwrap_or_else(\|e\| { ... })`) |

To bring one back, rewrite it against the language that exists and add it to
`examples/` with a `.expected` file — `tests/examples-test.sh` requires one, so
an example that stops working fails CI instead of rotting quietly.

Everything in `examples/` is compiled **and run** by that suite on every push.
