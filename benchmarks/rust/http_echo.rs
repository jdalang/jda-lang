// HTTP echo server benchmark — respond with fixed JSON (no deps, raw sockets)
// Measure with: wrk -t2 -c100 -d5s http://localhost:8080/
use std::io::{Read, Write};
use std::net::TcpListener;

const RESPONSE: &[u8] = b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 27\r\nConnection: keep-alive\r\n\r\n{\"status\":\"ok\",\"count\":42}";

fn main() {
    let listener = TcpListener::bind("0.0.0.0:8080").unwrap();
    eprintln!("Rust http_echo listening on :8080");
    let mut buf = [0u8; 4096];
    for stream in listener.incoming() {
        if let Ok(mut s) = stream {
            let _ = s.read(&mut buf);
            let _ = s.write_all(RESPONSE);
        }
    }
}
