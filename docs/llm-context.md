# Jda Language Reference for LLMs

This is a complete, self-contained reference for the Jda programming language. It contains everything needed to write correct Jda code. Feed this file into your LLM context window.

## What is Jda?

Jda is a compiled systems language that produces static x86-64 Linux ELF binaries. No runtime, no garbage collector, no libc. The compiler is self-hosted (written in Jda). It has 114 stdlib packages and compiles in ~42ms.

## Quick Start

```jda
fn main() -> i64 {
    print("Hello, world!\n")
    ret 0
}
```

Build and run:
```bash
jda build hello.jda -o hello
jda run hello.jda
```

---

## Types

| Type | Description | Example |
|------|-------------|---------|
| `i64` | 64-bit signed integer (default) | `let x = 42` |
| `i32` | 32-bit signed integer | `let y: i32 = 10` |
| `i16` | 16-bit signed integer | `let n: i16 = 1000` |
| `i8` | 8-bit signed byte | `let b: i8 = 65` |
| `u64` | 64-bit unsigned integer | `let n: u64 = 42` |
| `u32` | 32-bit unsigned integer | `let n: u32 = 100000` |
| `u16` | 16-bit unsigned integer | `let n: u16 = 65535` |
| `u8` | 8-bit unsigned integer | `let n: u8 = 255` |
| `f64` | 64-bit float | `let pi: f64 = 3.14` |
| `f32` | 32-bit float (f64 internally) | `let x: f32 = 2.0` |
| `&T` | Pointer/reference to T | `let p: &i64 = &x` |
| `&i8` | Byte buffer / C-string pointer | `let s: &i8 = "hello"` |

There is no dedicated `bool` type — `true` compiles to `1` and `false` compiles to `0` (both i64). Unsigned types use zero-extension for loads, unsigned comparisons (jb/ja), and unsigned division (DIV instead of IDIV).

## Variables

```jda
let x = 42              ; mutable variable, type inferred as i64
let name = "hello"      ; string literal (&i8 pointer)
let flag = true         ; boolean literal (true=1, false=0)
let ch = 'A'            ; char literal (ASCII value 65)
let pi: f64 = 3.14      ; explicit type annotation
const MAX = 100         ; compile-time constant
```

Char literals (`'x'`) produce the ASCII integer value. Supported escapes: `'\n'`→10, `'\t'`→9, `'\r'`→13, `'\0'`→0, `'\\'`→92, `'\''`→39.

All variables are mutable. There is no `mut` keyword.

## Functions

```jda
fn add(a: i64, b: i64) -> i64 {
    ret a + b
}

fn greet() {
    print("hello\n")
}

fn main() -> i64 {
    let sum = add(3, 4)
    print_i64(sum)
    print("\n")
    ret 0
}
```

**Rules:**
- Use `ret` (not `return`) to return a value
- `fn main() -> i64` is the entry point; return 0 for success
- `fn main()` (no return type) also works
- Maximum 6 parameters per function

## Operators

| Category | Operators |
|----------|-----------|
| Arithmetic | `+`, `-`, `*`, `/`, `%` |
| Comparison | `==`, `!=`, `<`, `>`, `<=`, `>=` |
| Logical | `and`, `or`, `not` |
| Compound assignment | `+=`, `-=`, `*=`, `/=` |
| Address-of | `&` (prefix) |
| Index | `[]` |
| Field access | `.` |

## Control Flow

### If/Else

```jda
if x > 0 {
    print("positive\n")
} else if x == 0 {
    print("zero\n")
} else {
    print("negative\n")
}
```

### Loops

```jda
; Conditional loop (like while)
let i = 0
loop i < 10 {
    print_i64(i)
    print("\n")
    i = i + 1
}

; For-range loop
for i in range(10) {
    print_i64(i)
    print("\n")
}

; Nested for loops
for i in range(3) {
    for j in range(4) {
        print_i64(i * 4 + j)
        print("\n")
    }
}
```

### Break and Continue

```jda
; break exits the loop immediately
let i = 0
loop i < 100 {
    if i == 10 { break }
    i = i + 1
}

; continue skips to next iteration (works in both loop and for)
let sum = 0
for i in range(10) {
    if i % 2 != 0 { continue }
    sum += i
}
```

**Important:** No unconditional `loop {}`. Always use `loop condition {}`:

```jda
let running = 1
loop running == 1 {
    ; ... do work ...
    if should_stop == 1 { running = 0 }
}
```

### Pattern Matching

```jda
match value {
    0 => print("zero\n")
    1 => print("one\n")
    _ => print("other\n")
}
```

## Strings and Printing

```jda
; String literals are &i8 pointers
print("hello world\n")       ; print string literal
print("tab\there\n")          ; \t, \n, \\, \" escapes supported

; Print integers
print_i64(42)                 ; prints "42"

; String interpolation (variable names only, no expressions)
let count = 5
print("found {count} items\n")    ; prints "found 5 items"

; Print with newline helper
let x = 100
print_i64(x)
print("\n")
```

**Important:** `print("{expr}")` does NOT work with expressions. Only variable names:
```jda
; WRONG:  print("{a + b}\n")
; RIGHT:
let sum = a + b
print("{sum}\n")
```

## Structs

```jda
struct Point {
    x: i64
    y: i64
}

fn main() -> i64 {
    let p = Point{}       ; create struct (fields zero-initialized)
    p.x = 10
    p.y = 20
    print_i64(p.x + p.y)
    print("\n")
    ret 0
}
```

### Struct Pointers

```jda
fn move_point(p: &Point, dx: i64, dy: i64) {
    p.x = p.x + dx
    p.y = p.y + dy
}

fn main() -> i64 {
    let p = Point{}
    p.x = 5
    p.y = 10
    move_point(&p, 3, 4)
    print_i64(p.x)        ; prints 8
    ret 0
}
```

### Arrays in Structs

```jda
struct Buffer {
    data: i64[256]
    len: i64
}
```

### Nested Structs

```jda
struct Rect {
    origin: Point
    width: i64
    height: i64
}

fn area(r: &Rect) -> i64 {
    ret r.width * r.height
}
```

## Traits and Impl

```jda
trait Shape {
    fn area(self: &Self) -> i64
}

struct Circle { radius: i64 }

impl Shape for Circle {
    fn area(self: &Circle) -> i64 {
        ret self.radius * self.radius * 3
    }
}

; Default methods in traits
trait Describable {
    fn name(self: &Self) -> i64       ; required
    fn describe(self: &Self) {         ; default implementation
        print("object\n")
    }
}
```

### Derive

```jda
derive(Debug, Eq, Clone, Hash, Zero, Ord)
struct Config {
    width: i64
    height: i64
}

; Generates: Config_debug(&c), Config_eq(&a, &b), Config_clone(&c),
;            Config_hash(&c), Config_zero(&c), Config_lt(&a, &b)
```

## Generics

```jda
fn identity<T>(x: T) -> T {
    ret x
}

let a = identity<i64>(42)
let b = identity<i32>(10)
```

### Const Generics

```jda
fn repeat<const N>() -> i64 {
    let sum = 0
    for i in range(N) {
        sum += 1
    }
    ret sum
}

let x = repeat<100>()
```

## Closures

```jda
let factor = 3
let scale = fn(x: i64) -> i64 { ret x * factor }
let result = call_closure(scale, 10)    ; returns 30
```

**Important:** Closures MUST capture at least one variable. A closure that captures nothing will segfault:

```jda
; WRONG — will segfault:
let double = fn(x: i64) -> i64 { ret x * 2 }

; RIGHT — capture a dummy variable:
let d = 0
let double = fn(x: i64) -> i64 { ret x * 2 + d }
```

## Enums

```jda
enum Color {
    Red = 0
    Green = 1
    Blue = 2
}

let c = Color::Red
```

## Memory Management

```jda
; Allocate 4KB memory page
let page: &i64 = alloc_pages(1)

; Read/write bytes
let byte = load_i8_at(buf, idx)     ; load byte at offset
poke_byte(buf, idx, val)            ; store byte at offset

; Direct Linux syscalls
let result = syscall(1, 1, buf, len)   ; write(stdout, buf, len)
```

**Important:** Use `poke_byte()` for byte stores. Direct indexed byte store (`buf[i] = val`) may not work correctly.

**Important:** Only call `alloc_pages` in `main()` or top-level functions, not in library helper functions (can cause memory overlap).

## Inline Assembly

```jda
asm {
    mov rax, 60
    xor rdi, rdi
    syscall
}
```

## Concurrency

```jda
; Channels
let ch = chan_new()

; Spawn green threads (J-Threads)
spawn {
    chan_send(ch, 42)
}

let val = chan_recv(ch)
print_i64(val)
```

## Comments

```jda
; Single-line comment
;; Documentation comment (used by jda-doc tool)
/* Multi-line block comment */

; Multi-line strings (literal newlines preserved):
print("line 1
line 2
")

; Raw strings (no escape processing):
let path = r"C:\Users\file.txt"
```

---

## Standard Library (114 packages)

Use `import` in source (preferred):
```jda
import "vec"
import "sort"
```

Or use `--include` on CLI (legacy):
```bash
jda build --include stdlib/vec.jda myapp.jda
```

### Data Structures
- **vec** — `vec_new()`, `vec_push(v, val)`, `vec_get(v, i)`, `vec_len(v)`, `vec_pop(v)`, `vec_set(v, i, val)`
- **hashmap** — `hashmap_new()`, `hashmap_set(m, key, val)`, `hashmap_get(m, key)`, `hashmap_has(m, key)`
- **set** — `set_new()`, `set_add(s, key)`, `set_has(s, key)`, `set_del(s, key)`
- **queue** — `queue_new()`, `queue_push(q, val)`, `queue_pop(q)`, `queue_len(q)`
- **heap** — `heap_new()`, `heap_push(h, val)`, `heap_pop(h)`, `heap_peek(h)`
- **ring** — `ring_new(cap)`, `ring_push(r, val)`, `ring_pop(r)`
- **matrix** — `matrix_new(rows, cols)`, `matrix_set(m, r, c, val)`, `matrix_get(m, r, c)`, `matrix_mul(a, b)`
- **tuple** — `pair_new(a, b)`, `pair_fst(p)`, `pair_snd(p)`

### Algorithms
- **sort** — `sort_vec(v)`, `sort_search(v, val)`, `sort_reverse(v)`, `sort_unique(v)`
- **iter** — `iter_map(v, f)`, `iter_filter(v, f)`, `iter_fold(v, init, f)`

### Strings and Encoding
- **string** — `str_len(s)`, `str_eq(a, b)`, `str_concat(a, b)`, `str_slice(s, start, len)`, `str_contains(s, sub)`
- **fmt** — `fmt_i64(buf, val)`, `fmt_hex(buf, val)`, `fmt_pad(buf, val, width)`
- **conv** — `conv_itoa(buf, val)`, `conv_atoi(s)`, `conv_hex(buf, val)`
- **json** — `json_parse(str)`, `json_get_str(obj, key)`, `json_get_i64(obj, key)`
- **csv** — `csv_parse(str)`, `csv_row_count(c)`, `csv_get(c, row, col)`
- **regex** — `regex_match(pattern, str)`, `regex_search(pattern, str)`
- **base64** — `base64_encode(buf, len)`, `base64_decode(str)`
- **uri** — `uri_parse(str)`, `uri_host(u)`, `uri_path(u)`, `uri_query(u)`

### I/O and Filesystem
- **fs** — `fs_open(path, flags)`, `fs_read(fd, buf, n)`, `fs_write(fd, buf, n)`, `fs_close(fd)`, `fs_exists(path)`, `fs_file_size(path)`, `fs_mkdir(path)`, `fs_unlink(path)`
- **file_io** — `fs_read_file(path, buf, max)`, `fs_write_file(path, buf, len)`, `file_read_all(fd)`, `file_read_line(fd)`
- **args** — `args_count()`, `args_get(i)`, `args_flag(name)`
- **find** — `find(root, pattern)` — recursive directory search

### Networking
- **net/tcp** — `tcp_socket()`, `tcp_bind(fd, port)`, `tcp_listen(fd, backlog)`, `tcp_accept(fd)`, `tcp_connect(host, port)`
- **net/http** — `http_parse_request(buf, len)`, `http_method(req)`, `http_path(req)`
- **dns** — `dns_lookup(hostname)` — resolve hostname to IPv4

### System
- **os** — `os_getenv(name)`, `os_exit(code)`, `os_getpid()`
- **time** — `time_now_ns()`, `time_now_ms()`, `time_sleep_ms(ms)`
- **process** — `process_fork()`, `process_exec(path, args)`, `process_wait(pid)`

### Math
- **math** — `math_abs(x)`, `math_min(a, b)`, `math_max(a, b)`, `math_pow(base, exp)`, `math_sqrt(x)`, `math_rand()`
- **bitops** — `bit_and(a, b)`, `bit_or(a, b)`, `bit_xor(a, b)`, `bit_shl(a, n)`, `bit_shr(a, n)`

### Crypto
- **crypto** — `sha256(buf, len)`, `aes_encrypt(key, plaintext)`, `hmac_sha256(key, msg)`
- **uuid** — `uuid_v4()` — generate random UUID

### Testing
- **testing** — `assert_eq(a, b)`, `assert_ne(a, b)`, `assert_true(x)`, `assert_gt(a, b)`
- **log** — `log_info(msg)`, `log_error(msg)`, `log_debug(msg)`

### AI/ML
- **tensor_ops** — `tensor_new(rows, cols)`, `tensor_set(t, r, c, val)`, `tensor_get(t, r, c)`, `tensor_matmul(a, b)`
- **autograd** — `ag_var(val)`, `ag_add(a, b)`, `ag_mul(a, b)`, `ag_backward(node)`
- **nn** — `nn_linear(in, out)`, `nn_forward(layer, input)`, `nn_sigmoid(x)`, `nn_mse_loss(pred, target)`

---

## Common Patterns

### Read a file

```jda
fn main() -> i64 {
    let path = "/tmp/test.txt"
    let buf = alloc_pages(4)       ; 16KB buffer
    let n = fs_read_file(path, buf, 16384)
    if n > 0 {
        print_str(buf, n)
    }
    ret 0
}
```

### Command-line arguments

```jda
fn main() -> i64 {
    let argc = args_count()
    if argc < 2 {
        print("Usage: prog <name>\n")
        ret 1
    }
    let name = args_get(1)
    print("Hello, ")
    print(name)
    print("!\n")
    ret 0
}
```

### Dynamic array (vec)

```jda
fn main() -> i64 {
    let v = vec_new()
    vec_push(v, 10)
    vec_push(v, 20)
    vec_push(v, 30)
    for i in range(vec_len(v)) {
        print_i64(vec_get(v, i))
        print("\n")
    }
    ret 0
}
```

### Hash map

```jda
fn main() -> i64 {
    let m = hashmap_new()
    hashmap_set(m, "name", "Jda")
    hashmap_set(m, "version", "1.0.0")
    let name = hashmap_get(m, "name")
    print(name)
    print("\n")
    ret 0
}
```

### Struct with methods

```jda
struct Counter {
    value: i64
}

fn counter_new() -> Counter {
    let c = Counter{}
    c.value = 0
    ret c
}

fn counter_inc(c: &Counter) {
    c.value = c.value + 1
}

fn counter_get(c: &Counter) -> i64 {
    ret c.value
}

fn main() -> i64 {
    let c = counter_new()
    counter_inc(&c)
    counter_inc(&c)
    counter_inc(&c)
    print_i64(counter_get(&c))   ; prints 3
    print("\n")
    ret 0
}
```

### TCP server

```jda
fn main() -> i64 {
    let fd = tcp_socket()
    tcp_bind(fd, 8080)
    tcp_listen(fd, 128)
    print("Listening on :8080\n")

    let running = 1
    loop running == 1 {
        let client = tcp_accept(fd)
        let buf = alloc_pages(1)
        let n = fs_read(client, buf, 4096)
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK"
        fs_write(client, response, 41)
        fs_close(client)
    }
    ret 0
}
```

### Fibonacci

```jda
fn fib(n: i64) -> i64 {
    if n <= 1 { ret n }
    ret fib(n - 1) + fib(n - 2)
}

fn main() -> i64 {
    print_i64(fib(35))
    print("\n")
    ret 0
}
```

### Sieve of Eratosthenes

```jda
fn main() -> i64 {
    let limit = 1000
    let sieve: &i64 = alloc_pages(1)

    ; Mark composites
    let i = 2
    loop i * i <= limit {
        if sieve[i] == 0 {
            let j = i * i
            loop j < limit {
                sieve[j] = 1
                j = j + i
            }
        }
        i = i + 1
    }

    ; Count primes
    let count = 0
    let k = 2
    loop k < limit {
        if sieve[k] == 0 {
            count = count + 1
        }
        k = k + 1
    }
    print_i64(count)
    print("\n")
    ret 0
}
```

---

## Critical Rules (Read Carefully)

These are compiler constraints that will cause bugs or crashes if ignored:

1. **Subtraction is right-associative.** `a - b - c` parses as `a - (b - c)`. Use temp variables:
   ```jda
   ; WRONG:  let x = a - b - c
   ; RIGHT:
   let tmp = a - b
   let x = tmp - c
   ```

2. **Max 6 function arguments.** The 7th argument gets garbage. Split into multiple calls or pass a struct pointer.

3. **Max 5 levels of if/else nesting.** Deeper nesting causes compiler issues. Extract to helper functions.

4. **No unconditional loops.** `loop { ... }` does not work. Always use `loop condition { ... }`.

5. **Closures must capture at least one variable.** Otherwise segfault.

7. **Use `poke_byte()` for byte stores.** `buf[i] = val` for byte arrays may not work.

8. **Max 1 syscall per function.** Multiple `syscall()` calls in one function can corrupt registers. Wrap each in its own function.

9. **String interpolation: variable names only.** `print("{a + b}")` does not work. Pre-compute into a variable.

10. **`alloc_pages()` only in main/top-level functions.** Calling from library helpers can cause memory overlap.

11. **No `as` casts in user programs.** They compile but segfault at runtime.

12. **String literals: pass directly to functions.** Don't store in a local then pass:
    ```jda
    ; WRONG:
    let s: &i8 = "hello"
    some_fn(s)              ; may segfault

    ; RIGHT:
    some_fn("hello")        ; pass literal directly
    ```

13. **No nested function calls in some contexts.** Pre-compute arguments:
    ```jda
    ; WRONG:  tensor_set(t, 0, 0, compute_val(x))
    ; RIGHT:
    let val = compute_val(x)
    tensor_set(t, 0, 0, val)
    ```

---

## Build Commands

```bash
# Compile
jda build hello.jda -o hello

# Compile and run
jda run hello.jda

# Include stdlib packages
jda build --include stdlib/vec.jda --include stdlib/sort.jda myapp.jda -o myapp

# Install packages locally
jda pkg install vec
jda pkg install sort
jda pkg search hash

# Format code
jda fmt myfile.jda

# Run tests
jda test tests/

# Show version
jda version
```

---

## Comparison with Other Languages

| Concept | Jda | C | Rust | Go | Python |
|---------|-----|---|------|----|--------|
| Entry point | `fn main() -> i64` | `int main()` | `fn main()` | `func main()` | `if __name__` |
| Print | `print("hi\n")` | `printf("hi\n")` | `println!("hi")` | `fmt.Println("hi")` | `print("hi")` |
| Variables | `let x = 5` | `int x = 5` | `let x = 5` | `x := 5` | `x = 5` |
| Loops | `loop i < n { }` | `while (i < n) { }` | `while i < n { }` | `for i < n { }` | `while i < n:` |
| For range | `for i in range(n)` | — | `for i in 0..n` | `for i := 0; i < n; i++` | `for i in range(n)` |
| Return | `ret x` | `return x` | `x` or `return x` | `return x` | `return x` |
| Structs | `struct P { x: i64 }` | `struct P { int x; }` | `struct P { x: i64 }` | `type P struct { X int }` | `@dataclass` |
| Traits | `trait T { }` | — | `trait T { }` | `interface T { }` | `class T(ABC):` |
| Pointers | `&T` | `T*` | `&T` | `*T` | — |
| Comments | `; comment` / `/* */` | `// comment` | `// comment` | `// comment` | `# comment` |
| Null | 0 | NULL | None/Option | nil | None |
| Package | `--include stdlib/x.jda` | `#include` | `use` | `import` | `import` |
