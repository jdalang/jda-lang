import time, sys
sys.setrecursionlimit(100000)

ORDER = 64
MAX_KEYS = ORDER - 1

class Node:
    __slots__ = ('keys', 'children', 'n', 'is_leaf')
    def __init__(self, leaf):
        self.keys = [0] * MAX_KEYS
        self.children = [-1] * ORDER
        self.n = 0
        self.is_leaf = leaf

nodes = []

def new_node(leaf):
    nd = Node(leaf)
    nodes.append(nd)
    return len(nodes) - 1

def search(nid, key):
    if nid < 0: return False
    nd = nodes[nid]
    i = 0
    while i < nd.n and key > nd.keys[i]: i += 1
    if i < nd.n and key == nd.keys[i]: return True
    if nd.is_leaf: return False
    return search(nd.children[i], key)

def split_child(parent, idx):
    full = nodes[parent].children[idx]
    mid = MAX_KEYS // 2
    right = new_node(nodes[full].is_leaf)
    rn = MAX_KEYS - mid - 1
    for j in range(rn):
        nodes[right].keys[j] = nodes[full].keys[mid + 1 + j]
    if not nodes[full].is_leaf:
        for j in range(rn + 1):
            nodes[right].children[j] = nodes[full].children[mid + 1 + j]
    promote_key = nodes[full].keys[mid]
    nodes[full].n = mid
    nodes[right].n = rn
    pn = nodes[parent].n
    j = pn
    while j > idx:
        nodes[parent].keys[j] = nodes[parent].keys[j-1]
        nodes[parent].children[j+1] = nodes[parent].children[j]
        j -= 1
    nodes[parent].keys[idx] = promote_key
    nodes[parent].children[idx + 1] = right
    nodes[parent].n += 1

def insert_nonfull(nid, key):
    nd = nodes[nid]
    if nd.is_leaf:
        i = nd.n - 1
        while i >= 0 and key < nd.keys[i]:
            nd.keys[i+1] = nd.keys[i]
            i -= 1
        if i >= 0 and nd.keys[i] == key: return
        nd.keys[i+1] = key
        nd.n += 1
    else:
        i = nd.n - 1
        while i >= 0 and key < nd.keys[i]: i -= 1
        if i >= 0 and nd.keys[i] == key: return
        i += 1
        ci = nd.children[i]
        if nodes[ci].n == MAX_KEYS:
            split_child(nid, i)
            if key > nodes[nid].keys[i]: i += 1
            if i < nodes[nid].n and key == nodes[nid].keys[i]: return
        insert_nonfull(nodes[nid].children[i], key)

root = 0

def insert(key):
    global root
    if nodes[root].n == MAX_KEYS:
        s = new_node(False)
        nodes[s].children[0] = root
        root = s
        split_child(s, 0)
        insert_nonfull(s, key)
    else:
        insert_nonfull(root, key)

rng_state = 12345
def next_rand():
    global rng_state
    rng_state = (rng_state * 1103515245 + 12345) & 0x7FFFFFFF
    return rng_state

N = 1000000
new_node(True)
t0 = time.monotonic()

rng_state = 12345
for _ in range(N): insert(next_rand() % (N * 10))

rng_state = 12345
found = 0
for _ in range(N):
    if search(root, next_rand() % (N * 10)): found += 1

rng_state = 99999
found2 = 0
for _ in range(N):
    if search(root, next_rand() % (N * 10)): found2 += 1

ms = int((time.monotonic() - t0) * 1000)
print(f"inserted: {N}")
print(f"found (known): {found}")
print(f"found (random): {found2}")
print(f"nodes: {len(nodes)}")
print(f"time: {ms} ms")
