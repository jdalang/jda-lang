# Jda Language Syntax Reference

## Comments

```jda
; Single-line comment
;; Documentation comment (extracted by jda-doc)

/* Multi-line comment */
/*
 * Block comment
 * spanning multiple lines
 */
```

## Imports

```jda
import "math"           ; imports stdlib/math.jda
import "vec"            ; imports stdlib/vec.jda
import "conv"           ; imports stdlib/conv.jda
```

Import statements must appear at the top of the file. The compiler resolves `import "name"` to `stdlib/<name>.jda` relative to the working directory. Duplicate imports are automatically skipped. The `--include` CLI flag is still supported for backward compatibility.

## Variables

```jda
let x = 42              ; mutable variable
let name = "hello"      ; string literal (pointer to data)
let flag = true         ; boolean literal (true=1, false=0)
let ch = 'A'            ; char literal (ASCII value 65)
const MAX = 100         ; compile-time constant
```

## Types

| Type | Description |
|------|-------------|
| `i64` | 64-bit signed integer (default) |
| `i32` | 32-bit signed integer |
| `i8` | 8-bit signed integer (byte) |
| `u64` | 64-bit unsigned integer |
| `u32` | 32-bit unsigned integer |
| `u16` | 16-bit unsigned integer |
| `u8` | 8-bit unsigned integer |
| `f64` | 64-bit floating point |
| `&T` | Pointer/reference to type T |
| `&i64` | Pointer to i64 array |
| `&i8` | Byte buffer pointer |

## Boolean and Character Literals

```jda
let a = true            ; boolean true (compiles to i64 1)
let b = false           ; boolean false (compiles to i64 0)
if a and not b { print("ok\n") }

let ch = 'A'            ; char literal → i64 65
let nl = '\n'           ; escape sequence → i64 10
let tab = '\t'          ; tab → i64 9
let zero = '\0'         ; null → i64 0
```

Booleans are syntactic sugar for i64 values. Char literals produce the ASCII integer value and support escape sequences: `\n`, `\t`, `\r`, `\0`, `\\`, `\'`.

## Functions

```jda
fn add(a: i64, b: i64) -> i64 {
    ret a + b
}

fn greet() {
    print("hello\n")
}
```

## Control Flow

### If/Else

```jda
if x > 0 {
    print("positive")
} else if x == 0 {
    print("zero")
} else {
    print("negative")
}
```

### Loops

```jda
let i = 0
loop i < 10 {
    print_i64(i)
    i = i + 1
}
```

**Note**: Unconditional loops use a guard variable: `loop run == 1 { ... }`

### For Loops

```jda
for i in range(10) { ... }         ; i = 0, 1, ..., 9
for i in range(3, 7) { ... }       ; i = 3, 4, 5, 6
```

### Break/Continue

```jda
; break exits the loop immediately
let i = 0
loop i < 100 {
    if i == 10 { break }
    i = i + 1
}

; continue skips to the next iteration
let sum = 0
for i in range(10) {
    if i % 2 != 0 { continue }
    sum += i
}
```

### Defer

```jda
fn cleanup() { print("cleanup\n") }

fn do_work() -> i64 {
    defer cleanup()          ; runs when do_work returns
    defer step_b()           ; multiple defers execute in LIFO order
    print("working\n")
    ret 42                   ; deferred calls run before ret
}
```

`defer fn()` schedules a function call to execute when the enclosing function returns. Multiple defers in the same function execute in reverse order (last-in, first-out). Deferred calls run before every `ret` statement and at the implicit function end.

## Operators

| Category | Operators |
|----------|-----------|
| Arithmetic | `+`, `-`, `*`, `/`, `%` |
| Comparison | `==`, `!=`, `<`, `>`, `<=`, `>=` |
| Logical | `and`, `or`, `not` |
| Address-of | `&` (prefix) |
| Index | `[]` |
| Field access | `.` |

## String Literals

```jda
print("hello world\n")    ; newline escape
print("tab\there")         ; tab
print("quote: \"hi\"")     ; escaped quotes
print("backslash: \\")     ; escaped backslash
```

### Multi-line Strings

Strings can span multiple lines — literal newlines are preserved:

```jda
print("line 1
line 2
line 3
")
```

### Raw Strings

Raw strings (prefixed with `r`) do not process escape sequences:

```jda
let path = r"C:\Users\docs\file.txt"   ; backslashes preserved
print(r"no \n escape here\n")          ; prints literal \n
```

## Inline Assembly

```jda
asm {
    mov rax, 60
    xor rdi, rdi
    syscall
}
```

## Syscalls

```jda
; Direct Linux syscall (up to 4 args)
let result = syscall(1, 1, buf, len)   ; write(stdout, buf, len)
```

## Memory

```jda
let page: &i64 = alloc_pages(1)    ; allocate 4KB page
let byte = load_i8_at(buf, idx)     ; load byte at offset
poke_byte(buf, idx, val)            ; store byte at offset
```
