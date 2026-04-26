import time

TABLE_SIZE = 1 << 20
MASK = TABLE_SIZE - 1
N = 600000

tbl_key = [0] * TABLE_SIZE
tbl_val = [0] * TABLE_SIZE
rng = 12345

def lcg():
    global rng
    rng = (rng * 1103515245 + 12345) & 2147483647
    return rng

def ht_hash(k): return (k * 2654435761) & MASK

def ht_insert(k, v):
    h = ht_hash(k)
    while tbl_key[h]:
        if tbl_key[h] == k: tbl_val[h] = v; return
        h = (h + 1) & MASK
    tbl_key[h] = k; tbl_val[h] = v

def ht_find(k):
    h = ht_hash(k)
    while tbl_key[h]:
        if tbl_key[h] == k: return 1
        h = (h + 1) & MASK
    return 0

t0 = time.perf_counter()
rng = 12345
for _ in range(N): k = lcg() | 1; ht_insert(k, k + 7)
rng = 12345
found_known = sum(ht_find(lcg() | 1) for _ in range(N))
rng = 99999
found_rand = sum(ht_find(lcg() | 1) for _ in range(N))
ms = int((time.perf_counter() - t0) * 1000)
print(f"inserted: {N}\nfound_known: {found_known}\nfound_rand: {found_rand}\ntime: {ms} ms")
