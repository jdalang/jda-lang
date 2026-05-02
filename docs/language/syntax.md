# Jda Language Syntax Reference

## Comments

```jda
; Single-line comment
;; Documentation comment (extracted by jda-doc)
```

## Variables

```jda
let x = 42              ; mutable variable
let name = "hello"      ; string literal (pointer to data)
const MAX = 100         ; compile-time constant
```

## Types

| Type | Description |
|------|-------------|
| `i64` | 64-bit signed integer (default) |
| `i32` | 32-bit signed integer |
| `i8` | 8-bit signed integer (byte) |
| `&T` | Pointer/reference to type T |
| `&i64` | Pointer to i64 array |
| `&i8` | Byte buffer pointer |

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

### Break/Continue

Use guard variables for early exit:

```jda
let done = 0
let i = 0
loop i < 100 and done == 0 {
    if arr[i] == target { done = 1 }
    if done == 0 { i = i + 1 }
}
```

## Operators

| Category | Operators |
|----------|-----------|
| Arithmetic | `+`, `-`, `*`, `/` |
| Comparison | `==`, `!=`, `<`, `>`, `<=`, `>=` |
| Logical | `and`, `or` |
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
