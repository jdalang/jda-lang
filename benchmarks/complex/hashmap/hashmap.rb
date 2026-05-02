TABLE_SIZE = 1 << 20
MASK = TABLE_SIZE - 1
N = 600_000

tbl_key = Array.new(TABLE_SIZE, 0)
tbl_val = Array.new(TABLE_SIZE, 0)
$rng = 12345

def lcg
  $rng = ($rng * 1103515245 + 12345) & 2147483647
  $rng
end
def ht_hash(k) = (k * 2654435761) & MASK
def ht_insert(tbl_key, tbl_val, k, v)
  h = ht_hash(k)
  while tbl_key[h] != 0
    if tbl_key[h] == k then tbl_val[h] = v; return end
    h = (h + 1) & MASK
  end
  tbl_key[h] = k; tbl_val[h] = v
end
def ht_find(tbl_key, k)
  h = ht_hash(k)
  while tbl_key[h] != 0
    return 1 if tbl_key[h] == k
    h = (h + 1) & MASK
  end
  0
end

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
$rng = 12345
N.times { k = lcg | 1; ht_insert(tbl_key, tbl_val, k, k + 7) }
$rng = 12345
found_known = N.times.sum { ht_find(tbl_key, lcg | 1) }
$rng = 99999
found_rand = N.times.sum { ht_find(tbl_key, lcg | 1) }
ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).to_i
puts "inserted: #{N}\nfound_known: #{found_known}\nfound_rand: #{found_rand}\ntime: #{ms} ms"
