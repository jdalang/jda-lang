ORDER = 64
MAX_KEYS = ORDER - 1

Node = Struct.new(:keys, :children, :n, :is_leaf)

$nodes = []

def new_node(leaf)
  nd = Node.new(Array.new(MAX_KEYS, 0), Array.new(ORDER, -1), 0, leaf)
  $nodes << nd
  $nodes.length - 1
end

def search(nid, key)
  return false if nid < 0
  nd = $nodes[nid]
  i = 0
  while i < nd.n && key > nd.keys[i]; i += 1; end
  return true if i < nd.n && key == nd.keys[i]
  return false if nd.is_leaf
  search(nd.children[i], key)
end

def split_child(parent, idx)
  full = $nodes[parent].children[idx]
  mid = MAX_KEYS / 2
  right = new_node($nodes[full].is_leaf)
  rn = MAX_KEYS - mid - 1
  rn.times { |j| $nodes[right].keys[j] = $nodes[full].keys[mid + 1 + j] }
  unless $nodes[full].is_leaf
    (rn + 1).times { |j| $nodes[right].children[j] = $nodes[full].children[mid + 1 + j] }
  end
  promote_key = $nodes[full].keys[mid]
  $nodes[full].n = mid
  $nodes[right].n = rn
  pn = $nodes[parent].n
  j = pn
  while j > idx
    $nodes[parent].keys[j] = $nodes[parent].keys[j-1]
    $nodes[parent].children[j+1] = $nodes[parent].children[j]
    j -= 1
  end
  $nodes[parent].keys[idx] = promote_key
  $nodes[parent].children[idx + 1] = right
  $nodes[parent].n += 1
end

def insert_nonfull(nid, key)
  nd = $nodes[nid]
  if nd.is_leaf
    i = nd.n - 1
    while i >= 0 && key < nd.keys[i]
      nd.keys[i+1] = nd.keys[i]; i -= 1
    end
    return if i >= 0 && nd.keys[i] == key
    nd.keys[i+1] = key; nd.n += 1
  else
    i = nd.n - 1
    while i >= 0 && key < nd.keys[i]; i -= 1; end
    return if i >= 0 && nd.keys[i] == key
    i += 1
    ci = nd.children[i]
    if $nodes[ci].n == MAX_KEYS
      split_child(nid, i)
      i += 1 if key > $nodes[nid].keys[i]
      return if i < $nodes[nid].n && key == $nodes[nid].keys[i]
    end
    insert_nonfull($nodes[nid].children[i], key)
  end
end

$root = new_node(true)

def insert(key)
  if $nodes[$root].n == MAX_KEYS
    s = new_node(false)
    $nodes[s].children[0] = $root
    $root = s
    split_child(s, 0)
    insert_nonfull(s, key)
  else
    insert_nonfull($root, key)
  end
end

$rng = 12345
def next_rand
  $rng = ($rng * 1103515245 + 12345) & 0x7FFFFFFF
  $rng
end

N = 1000000
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

$rng = 12345
N.times { insert(next_rand % (N * 10)) }

$rng = 12345
found = 0
N.times { found += 1 if search($root, next_rand % (N * 10)) }

$rng = 99999
found2 = 0
N.times { found2 += 1 if search($root, next_rand % (N * 10)) }

ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).to_i
puts "inserted: #{N}"
puts "found (known): #{found}"
puts "found (random): #{found2}"
puts "nodes: #{$nodes.length}"
puts "time: #{ms} ms"
