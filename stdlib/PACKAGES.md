# Jda Standard Library Packages

Use with `--include stdlib/<name>.jda` or add as a dependency in `jda.toml`.

| Package | Description |
|---------|-------------|
| array | Array literals and utilities — arr1–arr6, fill, range, copy, sort, reverse, sum/min/max |
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
| hashmap | Hash map — open addressing, linear probing, map_of1–of3 constructors, keys/values, copy, merge, print |
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
| option | Option type — Some/None, unwrap, unwrap_or, opt_or, opt_eq, print |
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
| slice | Slice / dynamic view — view into array, sub-slice, get/set, contains, sum, print |
| sort | Sorting — quicksort, binary search, reverse, unique, merge |
| string | String library — length-prefixed, from_cstr, concat, slice, replace, trim, split, join, cmp, reverse, pad, from_i64 |
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
| variant | Sum types / tagged unions — var0–var4, tag, field access, equality, print |
| vec | Dynamic arrays — push, pop, get, set, grow, contains, remove |
| bignum | Arbitrary precision integers — add, sub, mul, div, compare, string conversion |
| i128 | 128-bit integer arithmetic — add, sub, mul, cmp, shifts, bitwise, string conversion |
| complex | Complex number arithmetic — add, sub, mul, div, abs, conjugate |
| dns | DNS resolver — hostname lookup, /etc/resolv.conf parsing, UDP query |
| digest | Message digests — MD5, SHA-512 (extends crypto's SHA-256/SHA-1) |
| encoding | Character encoding — UTF-8 validation, char count, ASCII ops, Latin-1 |
| erb | Template engine — variable substitution, HTML escaping |
| fileutils | High-level file utilities — mkdir_p, rm_rf, cp, mv, touch, chmod |
| marshal | Binary serialization — dump/load i64, strings, arrays, maps (TLV format) |
| mutex | Mutex and condition variable — futex-based lock/unlock, condvar wait/signal |
| open3 | Child process I/O capture — popen, capture2, capture3, piped stdin/stdout |
| optparse | Rich CLI option parser — short/long flags, required args, help generation |
| pack | Binary pack/unpack — i8/i16/i32/i64 LE/BE, strings, raw bytes |
| pathname | Path manipulation — dirname, extname, normalize, is_absolute, join |
| range | Range type — inclusive/exclusive, step, contains, each, sum |
| rational | Rational number arithmetic — add, sub, mul, div, simplify via GCD |
| securerandom | Cryptographic random — getrandom(2), hex, base64, UUID v4 |
| signal | Signal handling — sig_action, ignore, default, raise, block/unblock |
| stringio | In-memory string I/O — read, write, seek, getline, putc/getc |
| stringscanner | Stateful string scanner — scan, check, skip, rest, eos, matched |
| tls | TLS 1.2 client — TCP connect, ClientHello, record layer |
| weakref | Weak references — deref, alive check, release, registry with sweep |
| yaml | YAML parser/emitter — key:value, lists, comments, quoted strings |
| zlib | Compression — CRC-32, Adler-32, deflate/inflate (stored blocks) |
| errno | System error codes — errno constants, strerror, error categories |
| platform | Platform detection — OS, arch, endianness, feature queries |
| enum | Enumeration utilities — define, iterate, name/value lookup |
| operator | Operator functions — arithmetic, comparison, logical as first-class fns |
| linecache | Line cache — read specific lines from files, cache management |
| textwrap | Text wrapping — wrap, fill, shorten, indent, dedent |
| fnmatch | Filename matching — Unix shell-style wildcards, pattern compile |
| diff | Text differencing — unified diff, line-by-line compare, edit distance |
| copy | Object copying — shallow copy, deep copy, clone helpers |
| mimetypes | MIME type detection — guess type from extension, register custom types |
| statistics | Statistical functions — mean, median, mode, stdev, variance, quantile |
| fixedpoint | Fixed-point arithmetic — add, sub, mul, div, round, scale conversion |
| datetime | Date and time — parse, format, add/sub duration, compare, timezone |
| calendar | Calendar utilities — month/year display, weekday, leap year, day-of-year |
| configparser | INI-style config parser — sections, keys, defaults, interpolation |
| toml | TOML parser/emitter — tables, arrays, inline tables, dotted keys |
| gzip | Gzip compression — compress, decompress, gzip header/footer |
| tarfile | Tar archive — create, extract, list, append, ustar format |
| zipfile | ZIP archive — create, extract, list, deflate/store methods |
| kvstore | Key-value store — persistent on-disk storage, get/set/delete, iteration |
| socketserver | Socket server framework — TCP/UDP, threading, request handlers |
| httpserver | HTTP server — request routing, static files, middleware, response writer |
| httpclient | HTTP client — GET/POST/PUT/DELETE, headers, response parsing |
| netrc | Netrc file parser — machine/login/password lookup, default entry |
| getpass | Password input — terminal echo suppression, secure prompt |
| sched | Task scheduler — delayed execution, periodic tasks, priority queue |
| mmap | Memory-mapped files — map, unmap, read, write, sync, advise |
| email | Email message — parse/compose RFC 5322, MIME parts, headers |
| htmlparser | HTML parser — tokenize, tag/attribute extraction, entity decode |
| xml | XML parser — SAX-style events, element tree, attributes, namespaces |
| smtp | SMTP client — connect, auth, send mail, STARTTLS, attachments |
| ftp | FTP client — connect, login, list, get, put, passive mode |
| compress | Compression codecs — LZ4, zstd-style frame format, streaming |
| glob | Glob pattern matching — recursive **, brace expansion, dotfiles |
