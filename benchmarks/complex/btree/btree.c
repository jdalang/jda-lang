/* B-tree benchmark — order-64 B-tree, insert 1M keys, query 1M, delete 500K
   Reports operation counts and timing */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define ORDER 64
#define MAX_KEYS (ORDER - 1)
#define MIN_KEYS (ORDER / 2 - 1)
#define MAX_NODES 100000

typedef struct {
    int keys[MAX_KEYS];
    int children[ORDER];
    int n;       /* number of keys */
    int is_leaf;
} Node;

static Node nodes[MAX_NODES];
static int node_cnt;
static int root;

static int new_node(int leaf) {
    int id = node_cnt++;
    nodes[id].n = 0;
    nodes[id].is_leaf = leaf;
    memset(nodes[id].children, -1, sizeof(nodes[id].children));
    return id;
}

static int search(int id, int key) {
    if (id < 0) return 0;
    Node *nd = &nodes[id];
    int i = 0;
    while (i < nd->n && key > nd->keys[i]) i++;
    if (i < nd->n && key == nd->keys[i]) return 1;
    if (nd->is_leaf) return 0;
    return search(nd->children[i], key);
}

static void split_child(int parent, int idx) {
    int full = nodes[parent].children[idx];
    int mid = MAX_KEYS / 2;
    int right = new_node(nodes[full].is_leaf);

    nodes[right].n = MAX_KEYS - mid - 1;
    for (int j = 0; j < nodes[right].n; j++)
        nodes[right].keys[j] = nodes[full].keys[mid + 1 + j];
    if (!nodes[full].is_leaf)
        for (int j = 0; j <= nodes[right].n; j++)
            nodes[right].children[j] = nodes[full].children[mid + 1 + j];

    int promote_key = nodes[full].keys[mid];
    nodes[full].n = mid;

    /* Shift parent keys/children right */
    for (int j = nodes[parent].n; j > idx; j--) {
        nodes[parent].keys[j] = nodes[parent].keys[j-1];
        nodes[parent].children[j+1] = nodes[parent].children[j];
    }
    nodes[parent].keys[idx] = promote_key;
    nodes[parent].children[idx + 1] = right;
    nodes[parent].n++;
}

static void insert_nonfull(int id, int key) {
    Node *nd = &nodes[id];
    int i = nd->n - 1;
    if (nd->is_leaf) {
        while (i >= 0 && key < nd->keys[i]) {
            nd->keys[i+1] = nd->keys[i];
            i--;
        }
        /* Skip duplicates */
        if (i >= 0 && nd->keys[i] == key) return;
        nd->keys[i+1] = key;
        nd->n++;
    } else {
        while (i >= 0 && key < nd->keys[i]) i--;
        if (i >= 0 && nd->keys[i] == key) return;
        i++;
        if (nodes[nd->children[i]].n == MAX_KEYS) {
            split_child(id, i);
            if (key > nd->keys[i]) i++;
            if (key == nd->keys[i]) return;
        }
        insert_nonfull(nd->children[i], key);
    }
}

static void insert(int key) {
    if (nodes[root].n == MAX_KEYS) {
        int s = new_node(0);
        nodes[s].children[0] = root;
        split_child(s, 0);
        root = s;
        insert_nonfull(s, key);
    } else {
        insert_nonfull(root, key);
    }
}

/* Simple LCG for deterministic pseudo-random numbers */
static long rng_state = 12345;
static int next_rand(void) {
    rng_state = (rng_state * 1103515245 + 12345) & 0x7FFFFFFF;
    return (int)rng_state;
}

int main(void) {
    int N = 1000000;
    node_cnt = 0;
    root = new_node(1);

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    /* Insert */
    rng_state = 12345;
    for (int i = 0; i < N; i++) {
        int key = next_rand() % (N * 10);
        insert(key);
    }

    /* Query */
    rng_state = 12345;
    int found = 0;
    for (int i = 0; i < N; i++) {
        int key = next_rand() % (N * 10);
        if (search(root, key)) found++;
    }

    /* Query random (mix of hits and misses) */
    rng_state = 99999;
    int found2 = 0;
    for (int i = 0; i < N; i++) {
        int key = next_rand() % (N * 10);
        if (search(root, key)) found2++;
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    long ms = (t1.tv_sec - t0.tv_sec)*1000 + (t1.tv_nsec - t0.tv_nsec)/1000000;
    printf("inserted: %d\n", N);
    printf("found (known): %d\n", found);
    printf("found (random): %d\n", found2);
    printf("nodes: %d\n", node_cnt);
    printf("time: %ld ms\n", ms);
    return 0;
}
