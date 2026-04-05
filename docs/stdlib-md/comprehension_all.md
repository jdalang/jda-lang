# comprehension_all

Dynamic Array (Vec<i64>)

## Functions

| Function | Description |
|----------|-------------|
| `vec_pages_for` | Pages needed for n i64 elements. |
| `vec_new` | Create a new vec with given initial capacity (minimum 16). |
| `vec_len` | Get length. |
| `vec_cap` | Get capacity. |
| `vec_grow` | Internal: grow the backing array to double capacity. |
| `vec_push` | Append an element. |
| `vec_pop` | Remove and return last element. Returns 0 if empty. |
| `vec_get` | Get element at index. |
| `vec_set` | Set element at index. |
| `vec_clear` | Reset length to 0 (does not free memory). |
| `vec_last` | Get last element (0 if empty). |
| `vec_contains` | Check if vec contains value. Returns 1 or 0. |
| `vec_remove` | Remove element at index, shift remaining left. Returns removed value. |
| `hash_i64` | Hash an i64 key (Knuth multiplicative hash). |
| `str_hash` | Hash a byte buffer (djb2). |
| `map_round_pow2` | Round up to next power of 2. Minimum 16. |
| `map_pages_for` | Pages needed for n i64 elements (8 bytes each, 4096 per page). |
| `map_new` | Create a new hash map with given capacity. |
| `map_len` | Get number of entries. |
| `map_find_slot` | Internal: find slot for key. Returns index. If key is found (state=1, keys ma... |
| `map_rehash` | Internal: rehash to double capacity. |
| `map_put` | Insert or update a key-value pair. |
| `map_get` | Get value for key. Returns 0 if not found. |
| `map_has` | Check if key exists. Returns 1 or 0. |
| `map_del` | Delete key. Returns 1 if found and deleted, 0 if not found. |
| `map_puts` | String-keyed insert: hash string, use hash as key. |
| `map_gets` | String-keyed lookup. |
| `map_hass` | String-keyed existence check. |
| `range` |  |
| `range2` |  |
| `range3` |  |
| `vec_comp_map` |  |
| `vec_comp_filter` |  |
| `vec_comp_map_filter` |  |
| `vec_sum` |  |
| `vec_any` |  |
| `vec_count` |  |
| `vec_each` |  |
| `vec_enumerate` |  |
| `vec_zip` |  |
| `vec_slice` |  |
| `vec_reverse` |  |
| `vec_sort` |  |
| `vec_min` |  |
| `vec_max` |  |
| `vec_flatten` |  |
| `vec_concat` |  |
| `vec_from_arr` |  |
| `map_from_vecs` |  |
| `map_keys` |  |
| `map_vals` |  |
| `map_items` |  |
| `map_comp_filter` |  |
| `map_comp_map_vals` |  |

### Details

#### `vec_pages_for`

```jda
fn vec_pages_for(n: i64) -> i64
```

Pages needed for n i64 elements.

#### `vec_new`

```jda
fn vec_new(cap: i64) -> &i64
```

Create a new vec with given initial capacity (minimum 16).

#### `vec_len`

```jda
fn vec_len(v: &i64) -> i64
```

Get length.

#### `vec_cap`

```jda
fn vec_cap(v: &i64) -> i64
```

Get capacity.

#### `vec_grow`

```jda
fn vec_grow(v: &i64)
```

Internal: grow the backing array to double capacity.

#### `vec_push`

```jda
fn vec_push(v: &i64, val: i64)
```

Append an element.

#### `vec_pop`

```jda
fn vec_pop(v: &i64) -> i64
```

Remove and return last element. Returns 0 if empty.

#### `vec_get`

```jda
fn vec_get(v: &i64, idx: i64) -> i64
```

Get element at index.

#### `vec_set`

```jda
fn vec_set(v: &i64, idx: i64, val: i64)
```

Set element at index.

#### `vec_clear`

```jda
fn vec_clear(v: &i64)
```

Reset length to 0 (does not free memory).

#### `vec_last`

```jda
fn vec_last(v: &i64) -> i64
```

Get last element (0 if empty).

#### `vec_contains`

```jda
fn vec_contains(v: &i64, val: i64) -> i64
```

Check if vec contains value. Returns 1 or 0.

#### `vec_remove`

```jda
fn vec_remove(v: &i64, idx: i64) -> i64
```

Remove element at index, shift remaining left. Returns removed value.

#### `hash_i64`

```jda
fn hash_i64(key: i64) -> i64
```

Hash an i64 key (Knuth multiplicative hash).

#### `str_hash`

```jda
fn str_hash(s: &i8, len: i64) -> i64
```

Hash a byte buffer (djb2).

#### `map_round_pow2`

```jda
fn map_round_pow2(n: i64) -> i64
```

Round up to next power of 2. Minimum 16.

#### `map_pages_for`

```jda
fn map_pages_for(n: i64) -> i64
```

Pages needed for n i64 elements (8 bytes each, 4096 per page).

#### `map_new`

```jda
fn map_new(cap: i64) -> &i64
```

Create a new hash map with given capacity.

#### `map_len`

```jda
fn map_len(m: &i64) -> i64
```

Get number of entries.

#### `map_find_slot`

```jda
fn map_find_slot(m: &i64, key: i64) -> i64
```

Internal: find slot for key. Returns index.
If key is found (state=1, keys match), returns that index.
If key is not found, returns the first empty or tombstone slot.

#### `map_rehash`

```jda
fn map_rehash(m: &i64)
```

Internal: rehash to double capacity.

#### `map_put`

```jda
fn map_put(m: &i64, key: i64, val: i64)
```

Insert or update a key-value pair.

#### `map_get`

```jda
fn map_get(m: &i64, key: i64) -> i64
```

Get value for key. Returns 0 if not found.

#### `map_has`

```jda
fn map_has(m: &i64, key: i64) -> i64
```

Check if key exists. Returns 1 or 0.

#### `map_del`

```jda
fn map_del(m: &i64, key: i64) -> i64
```

Delete key. Returns 1 if found and deleted, 0 if not found.

#### `map_puts`

```jda
fn map_puts(m: &i64, key: &i8, klen: i64, val: i64)
```

String-keyed insert: hash string, use hash as key.

#### `map_gets`

```jda
fn map_gets(m: &i64, key: &i8, klen: i64) -> i64
```

String-keyed lookup.

#### `map_hass`

```jda
fn map_hass(m: &i64, key: &i8, klen: i64) -> i64
```

String-keyed existence check.

#### `range`

```jda
fn range(stop: i64) -> &i64
```

#### `range2`

```jda
fn range2(start: i64, stop: i64) -> &i64
```

#### `range3`

```jda
fn range3(start: i64, stop: i64, step: i64) -> &i64
```

#### `vec_comp_map`

```jda
fn vec_comp_map(v: &i64, f: i64) -> &i64
```

#### `vec_comp_filter`

```jda
fn vec_comp_filter(v: &i64, pred: i64) -> &i64
```

#### `vec_comp_map_filter`

```jda
fn vec_comp_map_filter(v: &i64, f: i64, pred: i64) -> &i64
```

#### `vec_sum`

```jda
fn vec_sum(v: &i64) -> i64
```

#### `vec_any`

```jda
fn vec_any(v: &i64, pred: i64) -> i64
```

#### `vec_count`

```jda
fn vec_count(v: &i64, pred: i64) -> i64
```

#### `vec_each`

```jda
fn vec_each(v: &i64, f: i64)
```

#### `vec_enumerate`

```jda
fn vec_enumerate(v: &i64) -> &i64
```

#### `vec_zip`

```jda
fn vec_zip(a: &i64, b: &i64) -> &i64
```

#### `vec_slice`

```jda
fn vec_slice(v: &i64, start: i64, stop: i64) -> &i64
```

#### `vec_reverse`

```jda
fn vec_reverse(v: &i64) -> &i64
```

#### `vec_sort`

```jda
fn vec_sort(v: &i64) -> &i64
```

#### `vec_min`

```jda
fn vec_min(v: &i64) -> i64
```

#### `vec_max`

```jda
fn vec_max(v: &i64) -> i64
```

#### `vec_flatten`

```jda
fn vec_flatten(vecs: &i64, n: i64) -> &i64
```

#### `vec_concat`

```jda
fn vec_concat(a: &i64, b: &i64) -> &i64
```

#### `vec_from_arr`

```jda
fn vec_from_arr(arr: &i64, len: i64) -> &i64
```

#### `map_from_vecs`

```jda
fn map_from_vecs(keys: &i64, vals: &i64) -> &i64
```

#### `map_keys`

```jda
fn map_keys(m: &i64) -> &i64
```

#### `map_vals`

```jda
fn map_vals(m: &i64) -> &i64
```

#### `map_items`

```jda
fn map_items(m: &i64) -> &i64
```

#### `map_comp_filter`

```jda
fn map_comp_filter(m: &i64, pred: i64) -> &i64
```

#### `map_comp_map_vals`

```jda
fn map_comp_map_vals(m: &i64, f: i64) -> &i64
```

---

*Generated by `jda-doc-md`*
