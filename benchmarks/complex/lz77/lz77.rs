/* LZ77 compression benchmark — compress + decompress 1MB pseudo-random text */
use std::time::Instant;

const WINDOW_SIZE: usize = 4096;
const LOOKAHEAD: usize = 258;
const DATA_SIZE: usize = 1024 * 1024;

static mut RNG: i64 = 42;
fn next_rand() -> i64 {
    unsafe {
        RNG = (RNG.wrapping_mul(1103515245).wrapping_add(12345)) & 0x7FFFFFFF;
        RNG
    }
}

fn generate_data() -> Vec<u8> {
    let mut data = Vec::with_capacity(DATA_SIZE);
    while data.len() < DATA_SIZE {
        let r = next_rand();
        let rm = r % 3;
        if rm == 0 {
            data.push(b'a' + (next_rand() % 26) as u8);
        } else if rm == 1 {
            let len = 1 + (next_rand() % 8) as usize;
            for _ in 0..len {
                if data.len() >= DATA_SIZE { break; }
                data.push(b'a' + (next_rand() % 26) as u8);
            }
        } else {
            if data.len() > 20 {
                let src = (next_rand() as usize) % (data.len() - 1);
                let len = 3 + (next_rand() % 20) as usize;
                for i in 0..len {
                    if data.len() >= DATA_SIZE { break; }
                    let dl = data.len();
                    let b = data[src + (i % (dl - src))];
                    data.push(b);
                }
            } else {
                data.push(b'a' + (next_rand() % 26) as u8);
            }
        }
    }
    data.truncate(DATA_SIZE);
    data
}

fn lz77_compress(src: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(src.len() * 2);
    let mut sp = 0;
    while sp < src.len() {
        let mut best_off = 0usize;
        let mut best_len = 0usize;
        let win_start = if sp > WINDOW_SIZE { sp - WINDOW_SIZE } else { 0 };
        for i in win_start..sp {
            let mut len = 0;
            let max_len = (src.len() - sp - 1).min(LOOKAHEAD);
            while len < max_len && src[i + len] == src[sp + len] { len += 1; }
            if len > best_len { best_len = len; best_off = sp - i; }
        }
        if best_len >= 3 {
            out.push(1);
            out.push((best_off >> 8) as u8);
            out.push(best_off as u8);
            out.push(best_len as u8);
            sp += best_len;
            if sp < src.len() { out.push(src[sp]); sp += 1; }
            else { out.push(0); }
        } else {
            out.push(0);
            out.push(src[sp]);
            sp += 1;
        }
    }
    out
}

fn lz77_decompress(src: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(DATA_SIZE);
    let mut sp = 0;
    while sp < src.len() {
        if src[sp] == 1 {
            sp += 1;
            let offset = ((src[sp] as usize) << 8) | src[sp+1] as usize;
            sp += 2;
            let length = src[sp] as usize;
            sp += 1;
            let next = src[sp];
            sp += 1;
            let start = out.len() - offset;
            for i in 0..length { out.push(out[start + i]); }
            out.push(next);
        } else {
            sp += 1;
            out.push(src[sp]);
            sp += 1;
        }
    }
    out
}

fn main() {
    unsafe { RNG = 42; }
    let data = generate_data();
    let t0 = Instant::now();
    let compressed = lz77_compress(&data);
    let decompressed = lz77_decompress(&compressed);
    let verified = decompressed.len() == data.len() && data == decompressed;
    let ms = t0.elapsed().as_millis();
    println!("original: {}", DATA_SIZE);
    println!("compressed: {}", compressed.len());
    println!("ratio: {}%", compressed.len() * 100 / DATA_SIZE);
    println!("verified: {}", if verified { "yes" } else { "no" });
    println!("time: {} ms", ms);
}
