/* HTTP echo server benchmark — respond with fixed JSON to every request
 * Usage: ./http_echo (listens on port 8080)
 * Measure with: wrk -t2 -c100 -d5s http://localhost:8080/
 */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

static const char RESPONSE[] =
    "HTTP/1.1 200 OK\r\n"
    "Content-Type: application/json\r\n"
    "Content-Length: 27\r\n"
    "Connection: keep-alive\r\n"
    "\r\n"
    "{\"status\":\"ok\",\"count\":42}";

static const int RESP_LEN = sizeof(RESPONSE) - 1;

int main(void) {
    int srv = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_port = htons(8080),
        .sin_addr.s_addr = INADDR_ANY
    };
    bind(srv, (struct sockaddr *)&addr, sizeof(addr));
    listen(srv, 128);

    fprintf(stderr, "C http_echo listening on :8080\n");

    char buf[4096];
    while (1) {
        int cli = accept(srv, NULL, NULL);
        if (cli < 0) continue;
        /* Read request (minimal — just drain the buffer) */
        read(cli, buf, sizeof(buf));
        write(cli, RESPONSE, RESP_LEN);
        close(cli);
    }
    return 0;
}
