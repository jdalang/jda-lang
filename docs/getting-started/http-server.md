# Build an HTTP Server

Build a static file server that handles HTTP requests, serves files from disk, and returns proper status codes — in under 120 lines.

## Prerequisites

[Install Jda](../../README.md#installation), then verify: `jda --version`

## 1. Create the project

```bash
mkdir jda-serve && cd jda-serve
```

Create `serve.jda`:

```jda
; jda-serve — static HTTP file server
; Serves files from a directory on a given port.
;
; Usage: jda-serve [port] [root-dir]
;   Default: port 8080, root "."

; --- Byte helper ---
fn srv_byte(buf: &i8, idx: i64) -> i64 {
    ret buf[idx]
}

; --- Configuration ---
let g_port = 8080
let g_root: &i8 = "."
let g_root_len = 1

; --- Parse the HTTP request line to extract the path ---
fn parse_path(buf: &i8, len: i64, out: &i8) -> i64 {
    ; Find "GET " prefix, then extract path until space
    let start = 4  ; skip "GET "
    let path_len = 0

    let i = start
    loop i < len {
        let b = srv_byte(buf, i)
        if b == 32 { ret path_len }   ; space = end of path
        if b == 10 { ret path_len }   ; newline = end
        poke_byte(out, path_len, b)
        path_len += 1
        i += 1
    }
    ret path_len
}

; --- Build full filesystem path: root + request path ---
fn build_path(req_path: &i8, req_len: i64, out: &i8) -> i64 {
    let pos = 0

    ; Copy root directory
    for i in range(g_root_len) {
        let b = srv_byte(g_root, i)
        poke_byte(out, pos, b)
        pos += 1
    }

    ; Copy request path (already starts with /)
    for i in range(req_len) {
        let b = srv_byte(req_path, i)
        poke_byte(out, pos, b)
        pos += 1
    }

    ; If path ends with /, append "index.html"
    let last = srv_byte(req_path, req_len - 1)
    if last == 47 {
        let idx_name: &i8 = "index.html"
        for i in range(10) {
            let b = srv_byte(idx_name, i)
            poke_byte(out, pos, b)
            pos += 1
        }
    }

    ; Null terminate
    poke_byte(out, pos, 0)
    ret pos
}

; --- Send HTTP response ---
fn send_response(client_fd: i64, code: i64, body: &i8, body_len: i64) {
    let resp: &i8 = alloc_pages(2)
    let pos = 0

    ; Status line
    let ok_line: &i8 = "HTTP/1.1 200 OK\r\nContent-Length: "
    let nf_line: &i8 = "HTTP/1.1 404 Not Found\r\nContent-Length: "

    let status_line = ok_line
    let status_len = 32
    if code == 404 {
        status_line = nf_line
        status_len = 39
    }

    for i in range(status_len) {
        let b = srv_byte(status_line, i)
        poke_byte(resp, pos, b)
        pos += 1
    }

    ; Write content length as digits
    let num_buf: &i8 = alloc_pages(1)
    let nlen = conv_itoa(body_len, num_buf)
    for i in range(nlen) {
        let b = srv_byte(num_buf, i)
        poke_byte(resp, pos, b)
        pos += 1
    }

    ; End headers
    let crlf2: &i8 = "\r\n\r\n"
    for i in range(4) {
        let b = srv_byte(crlf2, i)
        poke_byte(resp, pos, b)
        pos += 1
    }

    ; Copy body
    for i in range(body_len) {
        let b = srv_byte(body, i)
        poke_byte(resp, pos, b)
        pos += 1
    }

    write(client_fd, resp, pos)
}

; --- Handle one client connection ---
fn handle_client(client_fd: i64) {
    let req_buf: &i8 = alloc_pages(2)    ; 8 KB for request
    let n = read(client_fd, req_buf, 8192)

    if n <= 0 {
        close(client_fd)
        ret
    }

    ; Parse request path
    let path_buf: &i8 = alloc_pages(1)
    let path_len = parse_path(req_buf, n, path_buf)

    ; Build filesystem path
    let full_path: &i8 = alloc_pages(1)
    let full_len = build_path(path_buf, path_len, full_path)

    ; Try to open the file
    let fd = open(full_path, 0, 0)
    if fd < 0 {
        let msg: &i8 = "404 Not Found"
        send_response(client_fd, 404, msg, 13)
        close(client_fd)
        ret
    }

    ; Read file contents
    let file_buf: &i8 = alloc_pages(256)  ; 1 MB max file
    let file_len = read(fd, file_buf, 1048576)
    close(fd)

    send_response(client_fd, 200, file_buf, file_len)
    close(client_fd)
}

; --- Main: bind, listen, accept loop ---
fn main() -> i64 {
    ; Create socket: socket(AF_INET=2, SOCK_STREAM=1, 0)
    let sock = syscall(41, 2, 1, 0)
    if sock < 0 {
        print("Failed to create socket\n")
        ret 1
    }

    ; Set SO_REUSEADDR
    let optval: &i64 = alloc_pages(1)
    optval[0] = 1
    syscall(54, sock, 1, 2, optval, 4)

    ; Bind: build sockaddr_in (port 8080)
    let addr: &i8 = alloc_pages(1)
    poke_byte(addr, 0, 2)    ; AF_INET (little-endian: family = 2)
    poke_byte(addr, 1, 0)
    ; Port 8080 = 0x1F90 → big-endian: 0x1F, 0x90
    poke_byte(addr, 2, 31)   ; 0x1F
    poke_byte(addr, 3, 144)  ; 0x90
    ; INADDR_ANY = 0.0.0.0
    poke_byte(addr, 4, 0)
    poke_byte(addr, 5, 0)
    poke_byte(addr, 6, 0)
    poke_byte(addr, 7, 0)

    let br = syscall(49, sock, addr, 16)
    if br < 0 {
        print("Failed to bind\n")
        ret 1
    }

    ; Listen
    syscall(50, sock, 128)

    print("Serving on http://localhost:8080\n")

    ; Accept loop
    let running = 1
    loop running == 1 {
        let client = syscall(43, sock, 0, 0)
        if client >= 0 {
            handle_client(client)
        }
    }

    ret 0
}
```

## 2. Build

```bash
jda build --include stdlib/prelude.jda --include stdlib/conv.jda \
    serve.jda -o jda-serve
```

## 3. Run

```bash
# Create a test page
echo '<h1>Hello from Jda!</h1>' > index.html

# Start the server
./jda-serve
# Serving on http://localhost:8080
```

In another terminal:

```bash
$ curl http://localhost:8080/
<h1>Hello from Jda!</h1>

$ curl http://localhost:8080/missing
404 Not Found
```

## How it works

The server uses **raw Linux syscalls** — no libc, no framework:

| Syscall | Number | Purpose |
|---------|--------|---------|
| `socket` | 41 | Create TCP socket |
| `setsockopt` | 54 | Set SO_REUSEADDR |
| `bind` | 49 | Bind to port |
| `listen` | 50 | Start listening |
| `accept` | 43 | Accept connection |
| `read` | 0 | Read request |
| `write` | 1 | Send response |
| `close` | 3 | Close fd |

The request handler is synchronous (one connection at a time). For concurrent handling, see the [web server example](../../examples/web_server.jda) which uses J-Threads to handle 10,000 simultaneous connections.

## What you learned

- **Raw syscalls** — `syscall(num, arg1, arg2, ...)` for direct kernel calls
- **`poke_byte`** — write individual bytes to buffers
- **`alloc_pages(n)`** — allocate n × 4KB pages
- **`for i in range(n)`** — iterate with new loop syntax
- **`conv_itoa`** — convert integers to strings
- **Jda builds static binaries** — the server is ~1 MB with zero dependencies

## Scaling up

For production use, the stdlib provides higher-level abstractions:

```jda
; Using stdlib socketserver + httpserver
let srv = srv_tcp_new(8080, 128)
srv_tcp_start(srv)

loop running == 1 {
    let client = srv_tcp_accept(srv)
    let req = http_parse_request(buf, len)
    let path_len = http_req_path(req, path_buf)
    let resp_len = http_respond_ok(body, body_len, resp_buf)
    write(client, resp_buf, resp_len)
    close(client)
}
```

## Next steps

- [Build a CLI Tool](cli-tool.md) — parse args, process files
- [Train a Neural Network](ml-example.md) — ML from scratch in Jda
