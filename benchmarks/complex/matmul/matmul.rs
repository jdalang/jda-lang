use std::time::Instant;
const N: usize = 256;
fn main() {
    let mut a = vec![0i64; N*N]; let mut b = vec![0i64; N*N]; let mut c = vec![0i64; N*N];
    for i in 0..N { for j in 0..N {
        a[i*N+j]=((i*7+j*13+1)%100) as i64; b[i*N+j]=((i*11+j*5+3)%100) as i64;
    }}
    let t0 = Instant::now();
    for i in 0..N { for j in 0..N {
        let mut s=0i64; for k in 0..N { s+=a[i*N+k]*b[k*N+j]; } c[i*N+j]=s;
    }}
    let ms = t0.elapsed().as_millis();
    let chk = c.iter().fold(0i64,|a,&x|(a+x)%1000000007);
    println!("n: {}\nchecksum: {}\ntime: {} ms", N, chk, ms);
}
