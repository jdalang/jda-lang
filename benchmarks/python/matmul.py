N = 200

a = [0] * (N * N)
b = [0] * (N * N)
c = [0] * (N * N)

for i in range(N):
    for j in range(N):
        a[i * N + j] = i + j
        b[i * N + j] = i * j + 1

for i in range(N):
    for j in range(N):
        s = 0
        for k in range(N):
            s += a[i * N + k] * b[k * N + j]
        c[i * N + j] = s

print(c[99 * N + 99])
