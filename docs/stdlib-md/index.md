# Jda Standard Library API Reference

Documentation for all 142 stdlib packages.

| Package | Description |
|---------|-------------|
| [args](args.md) | CLI Argument Parser |
| [array](array.md) | Array Literals and Utilities |
| [autograd](autograd.md) |  |
| [avx512_ops](avx512_ops.md) |  |
| [base64](base64.md) | Base64 Encoding/Decoding |
| [benchmark](benchmark.md) | In-Language Micro-Benchmarking |
| [bignum](bignum.md) | Arbitrary Precision Integers |
| [bitops](bitops.md) | Bit Manipulation Utilities |
| [buildconfig](buildconfig.md) | Build Configuration File (jda.toml) |
| [calendar](calendar.md) | Calendar Utilities |
| [complex](complex.md) | Complex Number Arithmetic |
| [comprehension_all](comprehension_all.md) | Dynamic Array (Vec<i64>) |
| [comprehension](comprehension.md) | List/Dict Comprehensions |
| [compress](compress.md) | Compression Utilities (RLE + LZ77 stubs) |
| [configparser](configparser.md) | INI File Parser |
| [context](context.md) |  |
| [conv](conv.md) | Value Conversions (itoa, atoi, hex) |
| [copy](copy.md) | Deep Copy Utilities |
| [crypto](crypto.md) | ; jda::crypto — Cryptographic primitives |
| [csv](csv.md) | CSV Reader/Writer |
| [dataclass](dataclass.md) | Data Class Utilities |
| [datetime](datetime.md) | Date, Time, and DateTime Functions |
| [debug](debug.md) | Software Debugger Toolkit |
| [decorator](decorator.md) | Decorator / Higher-Order Function Patterns |
| [diff](diff.md) | Sequence Comparison and Diff |
| [digest](digest.md) | Message Digest Algorithms |
| [dns](dns.md) | DNS Resolver |
| [drop](drop.md) | Destructors / Finalizers / Deterministic Cleanup |
| [email](email.md) | Email Message Parser/Composer |
| [encoding](encoding.md) | Character Encoding Utilities |
| [enum](enum.md) | Enumeration Type with Named Constants |
| [erb](erb.md) | Template Engine |
| [errno](errno.md) | Named Error Constants and Descriptions |
| [file_io_all](file_io_all.md) | Minimal File I/O |
| [file_io](file_io.md) | High-Level File I/O Helpers |
| [fileutils](fileutils.md) | High-Level File Utilities |
| [find](find.md) | Recursive Directory Traversal |
| [fixedpoint](fixedpoint.md) | Scaled Integer Arithmetic (4 Decimal Places) |
| [float_fmt](float_fmt.md) | Float Formatting Utilities |
| [fmt](fmt.md) | Minimal String Formatting |
| [fnmatch](fnmatch.md) | Filename Pattern Matching |
| [fs](fs.md) | Minimal File I/O |
| [ftp](ftp.md) | FTP Protocol Helpers |
| [getpass](getpass.md) | Password Input Helpers |
| [glob](glob.md) | Glob Pattern Matching (fnmatch-style) |
| [gzip](gzip.md) | Gzip Format (Stored Blocks Only) |
| [hashmap](hashmap.md) | Hash Map (i64 -> i64) |
| [heap](heap.md) | Binary Heap (generic min/max) |
| [htmlparser](htmlparser.md) | Simple HTML Tag Parser (SAX-style events) |
| [httpclient](httpclient.md) | HTTP Client Helpers |
| [httpserver](httpserver.md) | HTTP Server Helpers |
| [i128](i128.md) | 128-bit Integer Arithmetic |
| [io](io.md) | Buffered I/O and Stream Helpers |
| [ipaddr](ipaddr.md) | IP Address Parsing and Manipulation |
| [iter](iter.md) | Chainable Iterator Adapters |
| [json](json.md) | ; jda::json — Zero-Copy JSON Parser & Serialiser |
| [kvstore](kvstore.md) | Simple Key-Value Store |
| [linecache](linecache.md) | Random Access to Text Lines in Files |
| [lint](lint.md) | Code Style Checker / Linter Helpers |
| [lockfile](lockfile.md) | Lock File for Dependency Pinning |
| [log](log.md) | Structured Logging |
| [marshal](marshal.md) | Binary Serialization |
| [math](math.md) | Integer Math, Random Numbers, and Constants |
| [matrix](matrix.md) | Integer Matrix Operations |
| [mimetypes](mimetypes.md) | File Extension to MIME Type Mapping |
| [data](data.md) | ; jda::ml::data — DataLoader & Dataset Primitives |
| [metrics](metrics.md) | ; jda::ml::metrics — Model Evaluation Metrics |
| [nn](nn.md) | ; jda::ml::nn — Native Neural Network Standard Library |
| [mmap](mmap.md) | Memory-Mapped Region Utilities |
| [mutex](mutex.md) | Mutex and Condition Variable |
| [namespace](namespace.md) | Namespaces / Module Registry |
| [http](http.md) | ; jda::net::http — HTTP/1.1 Parser & Response Writer |
| [tcp](tcp.md) | ; jda::net::tcp — TCP Socket API |
| [udp](udp.md) | ; jda::net::udp — UDP Socket API |
| [ws](ws.md) | ; jda::net::ws — WebSocket Protocol (RFC 6455) |
| [netrc](netrc.md) | .netrc File Parser |
| [nn](nn.md) |  |
| [observer](observer.md) | Publish/Subscribe Event Pattern |
| [open3](open3.md) | Capture Child Process I/O |
| [operator](operator.md) | Operators as Functions |
| [option](option.md) | Option Type (nullable values) |
| [optparse](optparse.md) | Rich CLI Option Parser |
| [os](os.md) | Operating System Interface |
| [pack](pack.md) | Binary Pack/Unpack |
| [pathname](pathname.md) | Path Manipulation Utilities |
| [platform](platform.md) | Platform Detection and System Information |
| [plot](plot.md) | Terminal & SVG Visualization |
| [pp](pp.md) | Pretty Printer |
| [prelude](prelude.md) | Standard Library Prelude |
| [process](process.md) | ; jda::process — Process management |
| [profile](profile.md) | Function-Level Profiler |
| [ptx](ptx.md) |  |
| [queue](queue.md) | Queue, Stack, and Priority Queue |
| [random](random.md) | Pseudo-Random Number Generation (LCG) |
| [range](range.md) | Range Type |
| [rational](rational.md) | Rational Number Arithmetic |
| [regex](regex.md) | Regular Expression Matching |
| [result](result.md) | Standard Error Return Pattern |
| [ring](ring.md) | Ring Buffer (Circular Buffer) |
| [rocm](rocm.md) |  |
| [sched](sched.md) | Simple Task Scheduler (Min-Heap) |
| [securerandom](securerandom.md) | Cryptographic Random Number Generation |
| [select](select.md) |  |
| [semver](semver.md) | Semantic Versioning |
| [set](set.md) | Hash Set (Set<i64>) |
| [shell](shell.md) | Shell Word Splitting and Escaping |
| [signal](signal.md) | Signal Handling |
| [slice](slice.md) | Slice / Dynamic View |
| [smartptr](smartptr.md) | Smart Pointers (Box, Rc, Arc) |
| [smtp](smtp.md) | SMTP Protocol Helpers |
| [socketserver](socketserver.md) | TCP/UDP Server Primitives |
| [sort](sort.md) | Sorting Algorithms for Vec |
| [stacktrace](stacktrace.md) | Call Stack Trace on Crash |
| [statistics](statistics.md) | Statistical Functions (Integer-Scaled) |
| [string](string.md) | String Type |
| [stringio](stringio.md) | In-Memory String I/O |
| [stringscanner](stringscanner.md) | Stateful String Scanner |
| [sync](sync.md) | WaitGroup and Barrier Synchronization |
| [tarfile](tarfile.md) | POSIX ustar Tar Archive Format |
| [tempfile](tempfile.md) | Temporary Files and Directories |
| [tensor_ops](tensor_ops.md) |  |
| [tensor_slice](tensor_slice.md) |  |
| [testing](testing.md) | Test Framework and Assertions |
| [textwrap](textwrap.md) | Text Wrapping and Formatting |
| [time](time.md) | Clocks & Sleep |
| [timeout](timeout.md) | Deadline and Timeout Utilities |
| [tls](tls.md) | TLS 1.2 Client (Minimal) |
| [toml](toml.md) | Subset TOML Parser |
| [transformer](transformer.md) |  |
| [tsort](tsort.md) | Topological Sort |
| [tuple](tuple.md) | Tuples / Multiple Return Values |
| [uri](uri.md) | URI/URL Parsing and Encoding |
| [uuid](uuid.md) | UUID Generation |
| [variant](variant.md) | Sum Types / Tagged Unions |
| [vec](vec.md) | Dynamic Array (Vec<i64>) |
| [visibility](visibility.md) | Visibility Control (pub/private convention) |
| [vtable](vtable.md) | Dynamic Dispatch / Virtual Method Tables |
| [weakref](weakref.md) | Weak References |
| [xml](xml.md) | Simple XML Parser (SAX-style events) |
| [yaml](yaml.md) | YAML Parser/Emitter (Subset) |
| [zipfile](zipfile.md) | ZIP Archive Format (Stored Only) |
| [zlib](zlib.md) | Compression (CRC-32, Deflate/Inflate) |

---

*Generated by `jda-doc-md`*
