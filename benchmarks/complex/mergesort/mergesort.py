import time

N = 2_000_000
rng = 42

def lcg():
    global rng
    rng = (rng * 1103515245 + 12345) & 2147483647
    return rng

arr = [lcg() for _ in range(N)]
tmp = [0] * N

t0 = time.perf_counter()
w = 1
while w < N:
    lo = 0
    while lo < N:
        mid = min(lo + w, N)
        hi  = min(lo + 2*w, N)
        if mid < hi:
            i, j, k = lo, mid, lo
            while k < hi:
                if i < mid and (j >= hi or arr[i] <= arr[j]):
                    tmp[k] = arr[i]; i += 1
                else:
                    tmp[k] = arr[j]; j += 1
                k += 1
            arr[lo:hi] = tmp[lo:hi]
        lo += 2*w
    w *= 2
ms = int((time.perf_counter() - t0) * 1000)

ok = all(arr[i] <= arr[i+1] for i in range(N-1))
chk = sum(arr) & 0xffffffff
print(f"n: {N}\nsorted: {int(ok)}\nfirst: {arr[0]}\nlast: {arr[-1]}\nchecksum: {chk}\ntime: {ms} ms")
