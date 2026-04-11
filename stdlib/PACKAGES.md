# Jda Standard Library Packages

Use with `--include stdlib/<name>.jda` or add as a dependency in `jda.toml`.

| Package | Description |
|---------|-------------|
| args | CLI argument parser — flags, options (--key=val), positional args |
| autograd | Automatic differentiation — forward/backward pass, gradient tape |
| benchmark | In-language micro-benchmarking — ns/us/ms timers, iteration, ns/op reporting |
| avx512_ops | AVX-512 SIMD vector operations — add, mul, fma, reduce |
| base64 | Base64 encoding/decoding — RFC 4648 standard |
| bitops | Bit manipulation — and, or, xor, shift, popcount, rotate |
| comprehension | List/dict comprehensions — range, map, filter, sort, zip, enumerate |
| context | Context — cancel, timeout, deadline, parent chain |
| conv | Value conversions — itoa, atoi, hex, binary string conversions |
| crypto | Cryptographic primitives — SHA-256, HMAC, constant-time compare |
| csv | CSV reader/writer — parse rows, fields, quoted strings |
| dataclass | Data class utilities — comparison combinators (le/gt/ge/cmp), validation |
| decorator | Higher-order functions — apply, fold, map, filter, find, pipeline, zip_with |
| file_io | File I/O helpers — slurp, write, append, copy, rename, path ops, line parsing |
| find | Recursive directory traversal — walk, files-only, type detection |
| fmt | String formatting — sprintf-style format, pad, align |
| fs | Filesystem primitives — open, close, read, write, stat, mkdir, unlink |
| hashmap | Hash map — open addressing, linear probing, string keys, rehash |
| heap | Binary heap — min-heap, max-heap, heap sort |
| io | I/O utilities — buffered read/write, stdin/stdout helpers |
| ipaddr | IP address parsing — IPv4 parse/format, CIDR, private/loopback/multicast |
| iter | Chainable iterator adapters — map, filter, take, skip, fold, collect |
| json | JSON parser/serializer — parse, stringify, get/set by key |
| log | Structured logging — levels (trace/debug/info/warn/error/fatal), timestamps |
| math | Math functions — abs, min, max, clamp, pow, sqrt, gcd, lcm, rand |
| matrix | Integer matrix operations — add, mul, transpose, identity, trace |
| nn | Neural network — layers, activations, loss functions, SGD optimizer |
| observer | Publish/subscribe event pattern — event bus, topic handlers |
| os | OS interface — env vars, argv, exit, getpid |
| plot | Visualization — bar charts, line plots, histograms, scatter, heatmaps |
| pp | Pretty printer — vec, matrix, hex dump, labeled values for debugging |
| prelude | Common utilities automatically available |
| process | Process management — fork, exec, wait, pipe |
| queue | Queue, stack, priority queue — FIFO, LIFO, min-heap |
| regex | Regular expressions — match, search, count, character classes |
| ring | Ring buffer — fixed-capacity circular buffer, windowed data |
| select | Channel select — poll multiple channels, non-blocking receive |
| set | Hash set — add, has, del, union, intersect, diff, subset |
| shell | Shell word splitting and escaping — escape, quote, join, split |
| sort | Sorting — quicksort, binary search, reverse, unique, merge |
| string | String library — length-prefixed, eq, concat, slice, search, case |
| tensor_ops | Tensor operations — create, add, mul, matmul, transpose, reshape |
| tempfile | Temporary files and directories — create, read, write, remove |
| tensor_slice | Tensor slicing — broadcast, axis reduce, slice, concat, arange |
| testing | Test framework — assert_eq/ne/true/false/gt/lt, test runner, summary |
| time | Time utilities — clock, sleep, elapsed, timestamp |
| timeout | Deadline and timeout utilities — now, deadline, remaining, sleep_ms, timers |
| tsort | Topological sort — DAG ordering, cycle detection, dependency resolution |
| transformer | Transformer model — attention, feedforward, layer norm, softmax |
| tuple | Tuples — pair, triple, fst/snd/trd, result ok/err/unwrap |
| uri | URI/URL parsing — scheme, host, port, path, query, percent-encode/decode |
| uuid | UUID v4 generation — random UUIDs |
| vec | Dynamic arrays — push, pop, get, set, grow, contains, remove |
