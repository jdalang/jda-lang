import time
N = 256
A = [[(i*7+j*13+1)%100 for j in range(N)] for i in range(N)]
B = [[(i*11+j*5+3)%100 for j in range(N)] for i in range(N)]
t0 = time.perf_counter()
C = [[sum(A[i][k]*B[k][j] for k in range(N)) for j in range(N)] for i in range(N)]
ms = int((time.perf_counter()-t0)*1000)
chk = sum(C[i][j] for i in range(N) for j in range(N)) % 1000000007
print(f"n: {N}\nchecksum: {chk}\ntime: {ms} ms")
