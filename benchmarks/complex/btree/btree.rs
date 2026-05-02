/* B-tree benchmark — order-64, insert 1M keys, query 1M, delete 500K */
use std::time::Instant;

const ORDER: usize = 64;
const MAX_KEYS: usize = ORDER - 1;
const MAX_NODES: usize = 100000;

struct Node {
    keys: [i32; MAX_KEYS],
    children: [i32; ORDER],
    n: usize,
    is_leaf: bool,
}

impl Node {
    fn new(leaf: bool) -> Self {
        Node { keys: [0; MAX_KEYS], children: [-1; ORDER], n: 0, is_leaf: leaf }
    }
}

struct BTree {
    nodes: Vec<Node>,
    root: usize,
}

impl BTree {
    fn new() -> Self {
        let mut bt = BTree { nodes: Vec::with_capacity(MAX_NODES), root: 0 };
        bt.nodes.push(Node::new(true));
        bt
    }

    fn new_node(&mut self, leaf: bool) -> usize {
        let id = self.nodes.len();
        self.nodes.push(Node::new(leaf));
        id
    }

    fn search(&self, id: i32, key: i32) -> bool {
        if id < 0 { return false; }
        let nd = &self.nodes[id as usize];
        let mut i = 0;
        while i < nd.n && key > nd.keys[i] { i += 1; }
        if i < nd.n && key == nd.keys[i] { return true; }
        if nd.is_leaf { return false; }
        self.search(nd.children[i], key)
    }

    fn split_child(&mut self, parent: usize, idx: usize) {
        let full = self.nodes[parent].children[idx] as usize;
        let mid = MAX_KEYS / 2;
        let is_leaf = self.nodes[full].is_leaf;
        let right = self.new_node(is_leaf);

        let rn = MAX_KEYS - mid - 1;
        for j in 0..rn {
            self.nodes[right].keys[j] = self.nodes[full].keys[mid + 1 + j];
        }
        if !is_leaf {
            for j in 0..=rn {
                self.nodes[right].children[j] = self.nodes[full].children[mid + 1 + j];
            }
        }
        let promote_key = self.nodes[full].keys[mid];
        self.nodes[full].n = mid;
        self.nodes[right].n = rn;

        let pn = self.nodes[parent].n;
        let mut j = pn;
        while j > idx {
            self.nodes[parent].keys[j] = self.nodes[parent].keys[j-1];
            self.nodes[parent].children[j+1] = self.nodes[parent].children[j];
            j -= 1;
        }
        self.nodes[parent].keys[idx] = promote_key;
        self.nodes[parent].children[idx + 1] = right as i32;
        self.nodes[parent].n += 1;
    }

    fn insert_nonfull(&mut self, id: usize, key: i32) {
        let n = self.nodes[id].n;
        if self.nodes[id].is_leaf {
            let mut i = n as i32 - 1;
            while i >= 0 && key < self.nodes[id].keys[i as usize] {
                self.nodes[id].keys[(i+1) as usize] = self.nodes[id].keys[i as usize];
                i -= 1;
            }
            if i >= 0 && self.nodes[id].keys[i as usize] == key { return; }
            self.nodes[id].keys[(i+1) as usize] = key;
            self.nodes[id].n += 1;
        } else {
            let mut i = n as i32 - 1;
            while i >= 0 && key < self.nodes[id].keys[i as usize] { i -= 1; }
            if i >= 0 && self.nodes[id].keys[i as usize] == key { return; }
            i += 1;
            let ci = self.nodes[id].children[i as usize] as usize;
            if self.nodes[ci].n == MAX_KEYS {
                self.split_child(id, i as usize);
                if key > self.nodes[id].keys[i as usize] { i += 1; }
                if (i as usize) < self.nodes[id].n && key == self.nodes[id].keys[i as usize] { return; }
            }
            let ci = self.nodes[id].children[i as usize] as usize;
            self.insert_nonfull(ci, key);
        }
    }

    fn insert(&mut self, key: i32) {
        let rn = self.nodes[self.root].n;
        if rn == MAX_KEYS {
            let s = self.new_node(false);
            self.nodes[s].children[0] = self.root as i32;
            let old_root = self.root;
            self.root = s;
            self.split_child(s, 0);
            self.insert_nonfull(s, key);
        } else {
            let r = self.root;
            self.insert_nonfull(r, key);
        }
    }
}

static mut RNG: i64 = 12345;
fn next_rand() -> i32 {
    unsafe {
        RNG = (RNG.wrapping_mul(1103515245).wrapping_add(12345)) & 0x7FFFFFFF;
        RNG as i32
    }
}

fn main() {
    let n = 1_000_000;
    let mut bt = BTree::new();
    let t0 = Instant::now();

    unsafe { RNG = 12345; }
    for _ in 0..n { bt.insert(next_rand() % (n * 10)); }

    unsafe { RNG = 12345; }
    let mut found = 0;
    for _ in 0..n {
        if bt.search(bt.root as i32, next_rand() % (n * 10)) { found += 1; }
    }

    unsafe { RNG = 99999; }
    let mut found2 = 0;
    for _ in 0..n {
        if bt.search(bt.root as i32, next_rand() % (n * 10)) { found2 += 1; }
    }

    let ms = t0.elapsed().as_millis();
    println!("inserted: {}", n);
    println!("found (known): {}", found);
    println!("found (random): {}", found2);
    println!("nodes: {}", bt.nodes.len());
    println!("time: {} ms", ms);
}
