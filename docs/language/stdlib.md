# Jda Standard Library

Jda ships with 53 stdlib packages covering data structures, algorithms, I/O, networking, crypto, testing, and more.

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

### I/O and Filesystem
| Package | Description |
|---------|-------------|
| `fs` | Filesystem primitives — open, close, read, write, stat, mkdir |
| `file_io` | File helpers — slurp, write, append, copy, rename, path ops |
| `io` | Buffered read/write, stdin/stdout helpers |
| `find` | Recursive directory traversal — walk, type detection |
| `tempfile` | Secure temp file/directory creation and cleanup |

### Networking
| Package | Description |
|---------|-------------|
| `net/tcp` | TCP sockets via direct Linux syscalls |
| `net/udp` | UDP datagram sockets |
| `net/http` | HTTP/1.1 parser and response writer |
| `net/ws` | WebSocket protocol (RFC 6455) |
| `ipaddr` | IPv4 parse/format, CIDR, private/loopback detection |

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

### Crypto and Security
| Package | Description |
|---------|-------------|
| `crypto` | SHA-256, AES-128/256, HMAC, ChaCha20-Poly1305 |
| `uuid` | UUID v4 random generation |

### Math and Bit Operations
| Package | Description |
|---------|-------------|
| `math` | abs, min, max, pow, sqrt, gcd, lcm, rand |
| `bitops` | Bitwise and/or/xor/shift/popcount via arithmetic |

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
| `prelude` | Common utilities automatically available |
