# The agent loop

Jda emits diagnostics as JSON with stable `JDA-*` codes, so a program that
writes Jda can read its own errors instead of a human reading them.

```bash
$ jda check --json examples/agent-loop/hallucinated.jda
{"schema":1,"ok":false,"diagnostics":[{"code":"JDA-C005","severity":"error",
 "file":"examples/agent-loop/hallucinated.jda","line":8,"col":1,"end_col":1,
 "message":"unknown method","snippet":"    let s = n.to_string()"}]}

$ jda check --json examples/agent-loop/corrected.jda
{"schema":1,"ok":true,"diagnostics":[]}
```

`--json` is a contract, not a formatting option: `check --json` emits exactly
one JSON object on every path, including the fatal ones that carry no token
position. A client parsing the stream never receives a bare line of prose.
`tools/check-json-contract.sh` asserts that shape against every case in
`tests/rejected/`.

## Why `JDA-C005` exists

`n.to_string()` is not a Jda method. Until recently it compiled clean: a
call-shaped access that resolved to no field, no impl method and no primitive
method fell through as the receiver, so the binary ran and printed `0`.

That is the exact shape a hallucinated API takes, which makes it the worst
possible failure for a language meant to be written by a model — nothing in
the toolchain says anything is wrong. It is now a hard error.

See `docs/llm-context.md` for the full list of syntax that does not exist,
including the constructs that are still accepted and still wrong.
