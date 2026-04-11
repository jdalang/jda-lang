# Structs and OOP in Jda

Jda uses a **struct + trait + impl** model for object-oriented programming, similar to Rust. There are no classes — instead, data (structs) and behavior (functions, traits, impls) are composed together.

## Structs

Structs are value types with named fields:

```jda
struct Point {
    x: i64
    y: i64
}

fn main() -> i64 {
    let p = Point{}
    p.x = 10
    p.y = 20
    print_i64(p.x + p.y)    ; prints 30
    ret 0
}
```

### Struct Pointers

Pass structs by reference for efficiency:

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
    print_i64(p.x)    ; prints 8
    ret 0
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

### Arrays in Structs

```jda
struct Buffer {
    data: i64[256]
    len: i64
}
```

## Traits (Interfaces)

Traits define shared behavior:

```jda
trait Printable {
    fn show(self: &Self)
}

trait Sized {
    fn size(self: &Self) -> i64
}
```

### Default Methods

Traits can have default implementations:

```jda
trait Describable {
    fn name(self: &Self) -> i64       ; required — must implement
    fn describe(self: &Self) {         ; default — optional to override
        print("object")
    }
}
```

## Impl (Implementation)

Implement traits for structs:

```jda
struct Circle {
    radius: i64
}

impl Sized for Circle {
    fn size(self: &Circle) -> i64 {
        ret self.radius * self.radius * 3
    }
}
```

Multiple traits can be implemented for the same struct:

```jda
impl Printable for Circle {
    fn show(self: &Circle) {
        print("Circle(r=")
        print_i64(self.radius)
        print(")")
    }
}
```

## Derive

Auto-generate common trait implementations:

```jda
derive(Debug, Eq, Clone, Hash, Zero, Ord)
struct Config {
    width: i64
    height: i64
    depth: i64
}
```

| Derive | Generates |
|--------|-----------|
| `Debug` | `Config_debug(&c)` — print struct fields |
| `Eq` | `Config_eq(&a, &b)` — field-by-field equality |
| `Clone` | `Config_clone(&c)` — deep copy |
| `Hash` | `Config_hash(&c)` — hash of all fields |
| `Zero` | `Config_zero(&c)` — zero all fields |
| `Ord` | `Config_lt(&a, &b)` — lexicographic ordering |

## OOP Patterns

### Encapsulation

Group related functions with a naming convention:

```jda
struct Stack {
    data: &i64
    len: i64
    cap: i64
}

fn stack_new(cap: i64) -> &Stack { ... }
fn stack_push(s: &Stack, val: i64) { ... }
fn stack_pop(s: &Stack) -> i64 { ... }
fn stack_len(s: &Stack) -> i64 { ret s.len }
```

### Polymorphism via Traits

```jda
trait Shape {
    fn area(self: &Self) -> i64
}

struct Square { side: i64 }
struct Triangle { base: i64  height: i64 }

impl Shape for Square {
    fn area(self: &Square) -> i64 { ret self.side * self.side }
}

impl Shape for Triangle {
    fn area(self: &Triangle) -> i64 { ret self.base * self.height / 2 }
}
```

### Composition over Inheritance

Jda has no class inheritance. Use struct embedding and delegation:

```jda
struct Animal {
    legs: i64
    name_off: i64
    name_len: i64
}

struct Dog {
    animal: Animal
    breed_off: i64
    breed_len: i64
}

fn dog_legs(d: &Dog) -> i64 {
    ret d.animal.legs
}
```

## Generics

Type-parameterized functions via monomorphization:

```jda
fn identity<T>(x: T) -> T {
    ret x
}

; Creates identity_i64, identity_i32, etc.
let a = identity<i64>(42)
let b = identity<i32>(10)
```

### Const Generics

Compile-time integer parameters:

```jda
fn repeat<const N>() -> i64 {
    let sum = 0
    let i = 0
    loop i < N {
        sum = sum + 1
        i = i + 1
    }
    ret sum
}

let x = repeat<100>()    ; N = 100 at compile time
```

## Closures

Anonymous functions with variable capture:

```jda
let factor = 3
let scale = fn(x: i64) -> i64 { ret x * factor }
let result = call_closure(scale, 10)    ; returns 30
```

**Note**: Closures must capture at least one variable.

## Unsafe

Gate dangerous operations behind explicit `unsafe` blocks:

```jda
fn safe_function() {
    ; Normal code here

    unsafe {
        syscall(1, 1, buf, len)    ; syscalls require unsafe
        asm { nop }                 ; inline asm requires unsafe
    }
}

; Compile with --safe to enforce unsafe blocks
; jda build --safe myapp.jda
```
