fn main() {
    let limit = 1_000_000;
    let mut sieve = vec![false; limit + 1];
    let mut i = 2;
    while i * i <= limit {
        if !sieve[i] {
            let mut j = i * i;
            while j <= limit {
                sieve[j] = true;
                j += i;
            }
        }
        i += 1;
    }
    let mut count = 0;
    for i in 2..=limit {
        if !sieve[i] {
            count += 1;
        }
    }
    println!("{}", count);
}
