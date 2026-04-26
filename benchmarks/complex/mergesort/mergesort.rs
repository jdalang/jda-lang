use std::time::Instant;

const N: usize = 2_000_000;
static mut RNG: i64 = 42;

fn lcg() -> i64 { unsafe { RNG = (RNG*1103515245+12345)&2147483647; RNG } }

fn merge_run(arr: &mut [i64], tmp: &mut [i64], lo: usize, mid: usize, hi: usize) {
    let (mut i, mut j, mut k) = (lo, mid, lo);
    while k < hi {
        if i < mid && (j >= hi || arr[i] <= arr[j]) { tmp[k] = arr[i]; i += 1; }
        else { tmp[k] = arr[j]; j += 1; }
        k += 1;
    }
    arr[lo..hi].copy_from_slice(&tmp[lo..hi]);
}

fn main() {
    let mut arr = vec![0i64; N];
    let mut tmp = vec![0i64; N];
    for x in arr.iter_mut() { *x = lcg(); }
    let t0 = Instant::now();
    let mut w = 1;
    while w < N {
        let mut lo = 0;
        while lo < N {
            let mid = (lo + w).min(N);
            let hi = (lo + 2*w).min(N);
            if mid < hi { merge_run(&mut arr, &mut tmp, lo, mid, hi); }
            lo += 2*w;
        }
        w *= 2;
    }
    let ms = t0.elapsed().as_millis();
    let ok = arr.windows(2).all(|w| w[0] <= w[1]);
    let chk: i64 = arr.iter().fold(0i64, |a,&x| (a+x)&0xffffffff);
    println!("n: {}\nsorted: {}\nfirst: {}\nlast: {}\nchecksum: {}\ntime: {} ms",
             N, ok as i32, arr[0], arr[N-1], chk, ms);
}
