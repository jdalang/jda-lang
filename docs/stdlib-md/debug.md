# debug

Software Debugger Toolkit

## Functions

| Function | Description |
|----------|-------------|
| `_dbg_cstr_len` |  |
| `_dbg_write_out` |  |
| `_dbg_write_err` |  |
| `_dbg_exit_fail` |  |
| `_dbg_print_str` |  |
| `_dbg_print_str_err` |  |
| `_dbg_print_int` |  |
| `_dbg_print_hex` |  |
| `_dbg_byte_at` |  |
| `_dbg_read_stdin_byte` |  |
| `dbg_init` | Initialize the debugger. Call once at program start. |
| `dbg_enable` | Enable debug output. |
| `dbg_disable` | Disable debug output (all dbg_ calls become no-ops except assertions). |
| `dbg_is_enabled` | Check if debugger is enabled. |
| `dbg_print` | Print a debug message (if enabled). |
| `dbg_println` | Print a debug message with newline (if enabled). |
| `dbg_break` | Software breakpoint: print label and pause until Enter is pressed. |
| `dbg_inspect_int` | Print "name = val\n" |
| `dbg_inspect_hex` | Print "name = 0xval\n" |
| `dbg_inspect_ptr` | Print "name = @0xaddr\n" |
| `dbg_inspect_bool` | Print "name = true/false\n" |
| `_dbg_assert_fail` |  |
| `dbg_assert` | Assert condition is true (non-zero). Aborts with msg if false. |
| `dbg_assert_eq` | Assert a == b. Aborts with msg if not equal. |
| `dbg_assert_ne` | Assert a != b. Aborts with msg if equal. |
| `dbg_assert_gt` | Assert a > b. Aborts with msg if not. |
| `dbg_assert_lt` | Assert a < b. Aborts with msg if not. |
| `dbg_watch` | Register a watchpoint on slot (0-15). Watches the i64 at *ptr. |
| `dbg_unwatch` | Remove watchpoint from slot. |
| `dbg_watch_count` | Get number of active watchpoints. |
| `_dbg_check_one` |  |
| `dbg_check` | Check all watchpoints. Returns number of values that changed. |
| `dbg_counter_reset` | Reset the hit counter to 0. |
| `dbg_counter_inc` | Increment the hit counter. |
| `dbg_counter_get` | Get the current hit counter value. |
| `dbg_counter_print` | Print "label: N\n" |

### Details

#### `_dbg_cstr_len`

```jda
fn _dbg_cstr_len(s: &i8) -> i64
```

#### `_dbg_write_out`

```jda
fn _dbg_write_out(s: &i8, len: i64)
```

#### `_dbg_write_err`

```jda
fn _dbg_write_err(s: &i8, len: i64)
```

#### `_dbg_exit_fail`

```jda
fn _dbg_exit_fail()
```

#### `_dbg_print_str`

```jda
fn _dbg_print_str(s: &i8)
```

#### `_dbg_print_str_err`

```jda
fn _dbg_print_str_err(s: &i8)
```

#### `_dbg_print_int`

```jda
fn _dbg_print_int(val: i64)
```

#### `_dbg_print_hex`

```jda
fn _dbg_print_hex(val: i64)
```

#### `_dbg_byte_at`

```jda
fn _dbg_byte_at(buf: &i8, idx: i64) -> i64
```

#### `_dbg_read_stdin_byte`

```jda
fn _dbg_read_stdin_byte()
```

#### `dbg_init`

```jda
fn dbg_init()
```

Initialize the debugger. Call once at program start.

#### `dbg_enable`

```jda
fn dbg_enable()
```

Enable debug output.

#### `dbg_disable`

```jda
fn dbg_disable()
```

Disable debug output (all dbg_ calls become no-ops except assertions).

#### `dbg_is_enabled`

```jda
fn dbg_is_enabled() -> i64
```

Check if debugger is enabled.

#### `dbg_print`

```jda
fn dbg_print(msg: &i8)
```

Print a debug message (if enabled).

#### `dbg_println`

```jda
fn dbg_println(msg: &i8)
```

Print a debug message with newline (if enabled).

#### `dbg_break`

```jda
fn dbg_break(label: &i8)
```

Software breakpoint: print label and pause until Enter is pressed.

#### `dbg_inspect_int`

```jda
fn dbg_inspect_int(name: &i8, val: i64)
```

Print "name = val\n"

#### `dbg_inspect_hex`

```jda
fn dbg_inspect_hex(name: &i8, val: i64)
```

Print "name = 0xval\n"

#### `dbg_inspect_ptr`

```jda
fn dbg_inspect_ptr(name: &i8, ptr: i64)
```

Print "name = @0xaddr\n"

#### `dbg_inspect_bool`

```jda
fn dbg_inspect_bool(name: &i8, val: i64)
```

Print "name = true/false\n"

#### `_dbg_assert_fail`

```jda
fn _dbg_assert_fail(msg: &i8)
```

#### `dbg_assert`

```jda
fn dbg_assert(cond: i64, msg: &i8)
```

Assert condition is true (non-zero). Aborts with msg if false.

#### `dbg_assert_eq`

```jda
fn dbg_assert_eq(a: i64, b: i64, msg: &i8)
```

Assert a == b. Aborts with msg if not equal.

#### `dbg_assert_ne`

```jda
fn dbg_assert_ne(a: i64, b: i64, msg: &i8)
```

Assert a != b. Aborts with msg if equal.

#### `dbg_assert_gt`

```jda
fn dbg_assert_gt(a: i64, b: i64, msg: &i8)
```

Assert a > b. Aborts with msg if not.

#### `dbg_assert_lt`

```jda
fn dbg_assert_lt(a: i64, b: i64, msg: &i8)
```

Assert a < b. Aborts with msg if not.

#### `dbg_watch`

```jda
fn dbg_watch(slot: i64, name: &i8, ptr: &i64)
```

Register a watchpoint on slot (0-15). Watches the i64 at *ptr.

#### `dbg_unwatch`

```jda
fn dbg_unwatch(slot: i64)
```

Remove watchpoint from slot.

#### `dbg_watch_count`

```jda
fn dbg_watch_count() -> i64
```

Get number of active watchpoints.

#### `_dbg_check_one`

```jda
fn _dbg_check_one(slot: i64) -> i64
```

#### `dbg_check`

```jda
fn dbg_check() -> i64
```

Check all watchpoints. Returns number of values that changed.

#### `dbg_counter_reset`

```jda
fn dbg_counter_reset()
```

Reset the hit counter to 0.

#### `dbg_counter_inc`

```jda
fn dbg_counter_inc()
```

Increment the hit counter.

#### `dbg_counter_get`

```jda
fn dbg_counter_get() -> i64
```

Get the current hit counter value.

#### `dbg_counter_print`

```jda
fn dbg_counter_print(label: &i8)
```

Print "label: N\n"

---

*Generated by `jda-doc-md`*
