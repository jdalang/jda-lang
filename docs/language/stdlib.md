# Jda Standard Library

Jda ships with 114 stdlib packages covering data structures, algorithms, I/O, networking, crypto, testing, and more.

## Using the Standard Library

```bash
# Include a single package
jda build --include stdlib/vec.jda myapp.jda

# Include the prelude (fs, fmt, time)
jda build --include stdlib/prelude.jda myapp.jda

# Include multiple packages
jda build --include stdlib/vec.jda --include stdlib/sort.jda myapp.jda
```

## Installing Packages Locally

```bash
jda pkg install vec          # copies stdlib/vec.jda → lib/vec.jda
jda pkg install sort         # copies stdlib/sort.jda → lib/sort.jda
jda pkg list                 # show installed packages
jda pkg search hash          # search for packages by keyword
```

## Package Categories

### Data Structures
| Package | Description |
|---------|-------------|
| `vec` | Dynamic arrays — push, pop, get, set, grow, contains, remove |
| `hashmap` | Hash map — open addressing, linear probing, string keys, rehash |
| `set` | Hash set — add, has, del, union, intersect, diff, subset |
| `queue` | Queue (FIFO), stack (LIFO), priority queue (min-heap) |
| `heap` | Binary heap — min-heap, max-heap, heap sort |
| `ring` | Ring buffer — fixed-capacity circular buffer |
| `matrix` | Integer matrix — add, mul, transpose, identity, trace |
| `tuple` | Tuples — pair, triple, fst/snd/trd, result ok/err/unwrap |

### Algorithms
| Package | Description |
|---------|-------------|
| `sort` | Quicksort, binary search, reverse, unique, merge sorted vecs |
| `iter` | Chainable iterator adapters — map, filter, take, skip, fold, collect |
| `comprehension` | List/dict comprehensions — range, map, filter, sort, zip |
| `tsort` | Topological sort — DAG ordering, cycle detection |

### Strings and Encoding
| Package | Description |
|---------|-------------|
| `string` | Length-prefixed strings — eq, concat, slice, search, case |
| `fmt` | String formatting — sprintf-style format, pad, align |
| `conv` | Value conversions — itoa, atoi, hex, binary |
| `regex` | Regular expressions — match, search, count, character classes |
| `base64` | Base64 encoding/decoding (RFC 4648) |
| `json` | JSON parser/serializer — parse, stringify, get/set by key |
| `csv` | CSV reader/writer — parse rows, quoted fields |
| `uri` | URL parsing — scheme, host, path, query, percent-encode/decode |
| `textwrap` | Text wrapping — wrap, fill, shorten, indent, dedent |
| `fnmatch` | Filename matching — Unix shell-style wildcards |
| `diff` | Text differencing — unified diff, line-by-line compare |
| `toml` | TOML parser/emitter — tables, arrays, inline tables |
| `configparser` | INI-style config parser — sections, keys, defaults |
| `mimetypes` | MIME type detection — guess type from extension |
| `htmlparser` | HTML parser — tokenize, tag/attribute extraction |
| `xml` | XML parser — SAX-style events, element tree, namespaces |
| `email` | Email message — parse/compose RFC 5322, MIME parts |

### I/O and Filesystem
| Package | Description |
|---------|-------------|
| `fs` | Filesystem primitives — open, close, read, write, stat, mkdir |
| `file_io` | File helpers — slurp, write, append, copy, rename, path ops |
| `io` | Buffered read/write, stdin/stdout helpers |
| `find` | Recursive directory traversal — walk, type detection |
| `tempfile` | Secure temp file/directory creation and cleanup |
| `glob` | Glob pattern matching — recursive **, brace expansion |
| `mmap` | Memory-mapped files — map, unmap, read, write, sync |
| `gzip` | Gzip compression — compress, decompress, header/footer |
| `tarfile` | Tar archive — create, extract, list, ustar format |
| `zipfile` | ZIP archive — create, extract, deflate/store methods |
| `linecache` | Line cache — read specific lines from files |
| `copy` | Object copying — shallow copy, deep copy, clone helpers |

### Networking
| Package | Description |
|---------|-------------|
| `net/tcp` | TCP sockets via direct Linux syscalls |
| `net/udp` | UDP datagram sockets |
| `net/http` | HTTP/1.1 parser and response writer |
| `net/ws` | WebSocket protocol (RFC 6455) |
| `ipaddr` | IPv4 parse/format, CIDR, private/loopback detection |
| `dns` | DNS resolver — hostname lookup, UDP query |
| `socketserver` | Socket server framework — TCP/UDP, request handlers |
| `httpserver` | HTTP server — routing, static files, middleware |
| `httpclient` | HTTP client — GET/POST/PUT/DELETE, response parsing |
| `smtp` | SMTP client — connect, auth, send mail, STARTTLS |
| `ftp` | FTP client — connect, login, list, get, put |
| `netrc` | Netrc file parser — machine/login/password lookup |

### System
| Package | Description |
|---------|-------------|
| `os` | Environment variables, argv, exit, getpid |
| `process` | Process management — fork, exec, wait, pipe |
| `time` | Clock, sleep, elapsed, timestamp |
| `timeout` | Deadline/timer utilities, sleep_ms |
| `context` | Context — cancel, timeout, deadline, parent chain |
| `select` | Channel select — poll multiple channels |
| `args` | CLI argument parser — flags, --key=val options |
| `shell` | Shell word escaping and splitting |
| `signal` | Signal handling — sig_action, ignore, raise, block/unblock |
| `platform` | Platform detection — OS, arch, endianness, features |
| `errno` | System error codes — errno constants, strerror |
| `getpass` | Password input — terminal echo suppression, secure prompt |
| `sched` | Task scheduler — delayed execution, periodic tasks |

### Crypto and Security
| Package | Description |
|---------|-------------|
| `crypto` | SHA-256, AES-128/256, HMAC, ChaCha20-Poly1305 |
| `uuid` | UUID v4 random generation |
| `securerandom` | Cryptographic random — hex, base64, UUID v4 |
| `digest` | Message digests — MD5, SHA-512 |

### Math and Bit Operations
| Package | Description |
|---------|-------------|
| `math` | abs, min, max, pow, sqrt, gcd, lcm, rand |
| `bitops` | Bitwise and/or/xor/shift/popcount via arithmetic |
| `statistics` | Statistical functions — mean, median, stdev, variance |
| `fixedpoint` | Fixed-point arithmetic — add, sub, mul, div, round |
| `bignum` | Arbitrary precision integers — add, sub, mul, div |
| `complex` | Complex number arithmetic — add, sub, mul, abs |
| `rational` | Rational number arithmetic — add, sub, mul, simplify |
| `datetime` | Date and time — parse, format, duration, timezone |
| `calendar` | Calendar utilities — month display, weekday, leap year |

### Testing and Development
| Package | Description |
|---------|-------------|
| `testing` | Test assertions — assert_eq/ne/true/false/gt/lt, runner |
| `benchmark` | In-language micro-benchmarking — ns/op timers |
| `log` | Structured logging — trace/debug/info/warn/error/fatal |
| `pp` | Pretty printer — vecs, matrices, hex dumps, labeled values |

### AI / ML
| Package | Description |
|---------|-------------|
| `tensor_ops` | Tensor create, add, mul, matmul, transpose, reshape |
| `tensor_slice` | Tensor slicing, broadcasting, axis reduction |
| `autograd` | Automatic differentiation — forward/backward, gradient tape |
| `nn` | Neural network — layers, activations, loss, SGD optimizer |
| `transformer` | Transformer model — attention, feedforward, softmax |

### GPU
| Package | Description |
|---------|-------------|
| `avx512_ops` | AVX-512 SIMD vector operations |
| `ptx` | NVIDIA PTX/CUDA operations |
| `rocm` | AMD ROCm/HIP operations |

### Patterns
| Package | Description |
|---------|-------------|
| `decorator` | Higher-order functions — apply, fold, map, pipeline |
| `dataclass` | Comparison combinators, validation utilities |
| `observer` | Publish/subscribe event bus |
| `enum` | Enumeration utilities — define, iterate, name/value lookup |
| `operator` | Operator functions — arithmetic, comparison as first-class fns |
| `kvstore` | Key-value store — persistent on-disk storage, get/set/delete |
| `compress` | Compression codecs — LZ4, zstd-style, streaming |
| `marshal` | Binary serialization — dump/load i64, strings, arrays, TLV |
| `pack` | Binary pack/unpack — i8/i16/i32/i64 LE/BE, strings |
| `encoding` | Character encoding — UTF-8, ASCII, Latin-1 |
| `erb` | Template engine — variable substitution, HTML escaping |
| `prelude` | Common utilities automatically available |
