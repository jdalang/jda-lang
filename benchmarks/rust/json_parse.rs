// JSON parse benchmark — parse array of objects, sum "value" fields
// Manual parser (no serde — single-file benchmark, no cargo)
use std::fmt::Write;

const NUM_OBJECTS: usize = 50000;

fn generate_json(n: usize) -> String {
    let mut s = String::with_capacity(n * 40);
    s.push('[');
    for i in 0..n {
        if i > 0 { s.push(','); }
        write!(s, r#"{{"id":{},"value":{}}}"#, i, 100 + (i % 1000)).unwrap();
    }
    s.push(']');
    s
}

fn parse_and_sum(json: &[u8]) -> i64 {
    let mut total: i64 = 0;
    let len = json.len();
    let mut i = 0;
    // Scan for "value": pattern
    while i + 8 < len {
        if json[i] == b'"' && json[i+1] == b'v' && json[i+2] == b'a'
            && json[i+3] == b'l' && json[i+4] == b'u' && json[i+5] == b'e'
            && json[i+6] == b'"' && json[i+7] == b':' {
            i += 8;
            let mut val: i64 = 0;
            let mut neg = false;
            if i < len && json[i] == b'-' { neg = true; i += 1; }
            while i < len && json[i] >= b'0' && json[i] <= b'9' {
                val = val * 10 + (json[i] - b'0') as i64;
                i += 1;
            }
            if neg { val = -val; }
            total += val;
        } else {
            i += 1;
        }
    }
    total
}

fn main() {
    let json = generate_json(NUM_OBJECTS);
    let sum = parse_and_sum(json.as_bytes());
    println!("len={} sum={}", json.len(), sum);
}
