use std::time::Instant;

const TABLE_SIZE: usize = 1 << 20;
const MASK: i64 = (TABLE_SIZE - 1) as i64;
const N: usize = 600000;

static mut TBL_KEY: [i64; TABLE_SIZE] = [0; TABLE_SIZE];
static mut TBL_VAL: [i64; TABLE_SIZE] = [0; TABLE_SIZE];
static mut RNG: i64 = 12345;

fn lcg() -> i64 {
    unsafe { RNG = (RNG * 1103515245 + 12345) & 2147483647; RNG }
}
fn ht_hash(k: i64) -> i64 { (k.wrapping_mul(2654435761u64 as i64)) & MASK }
fn ht_insert(k: i64, v: i64) {
    unsafe {
        let mut h = ht_hash(k) as usize;
        while TBL_KEY[h] != 0 { if TBL_KEY[h]==k{TBL_VAL[h]=v;return;} h=(h+1)&(TABLE_SIZE-1); }
        TBL_KEY[h]=k; TBL_VAL[h]=v;
    }
}
fn ht_find(k: i64) -> i64 {
    unsafe {
        let mut h = ht_hash(k) as usize;
        while TBL_KEY[h] != 0 { if TBL_KEY[h]==k{return 1;} h=(h+1)&(TABLE_SIZE-1); }
        0
    }
}

fn main() {
    let t0 = Instant::now();
    unsafe { RNG = 12345; }
    for _ in 0..N { let k = lcg()|1; ht_insert(k, k+7); }
    unsafe { RNG = 12345; }
    let mut found_known: i64 = 0;
    for _ in 0..N { let k = lcg()|1; found_known += ht_find(k); }
    unsafe { RNG = 99999; }
    let mut found_rand: i64 = 0;
    for _ in 0..N { let k = lcg()|1; found_rand += ht_find(k); }
    let ms = t0.elapsed().as_millis();
    println!("inserted: {}\nfound_known: {}\nfound_rand: {}\ntime: {} ms",
             N, found_known, found_rand, ms);
}
