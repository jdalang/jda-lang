const N: usize = 200;

fn main() {
    let mut a = vec![0i64; N * N];
    let mut b = vec![0i64; N * N];
    let mut c = vec![0i64; N * N];

    for i in 0..N {
        for j in 0..N {
            a[i * N + j] = (i + j) as i64;
            b[i * N + j] = (i * j + 1) as i64;
        }
    }

    for i in 0..N {
        for j in 0..N {
            let mut sum: i64 = 0;
            for k in 0..N {
                sum += a[i * N + k] * b[k * N + j];
            }
            c[i * N + j] = sum;
        }
    }

    println!("{}", c[99 * N + 99]);
}
