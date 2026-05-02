import time

WINDOW_SIZE = 4096
LOOKAHEAD = 258
DATA_SIZE = 1024 * 1024

rng_state = 42
def next_rand():
    global rng_state
    rng_state = (rng_state * 1103515245 + 12345) & 0x7FFFFFFF
    return rng_state

def generate_data():
    data = bytearray()
    while len(data) < DATA_SIZE:
        r = next_rand()
        rm = r % 3
        if rm == 0:
            data.append(ord('a') + next_rand() % 26)
        elif rm == 1:
            l = 1 + next_rand() % 8
            for _ in range(l):
                if len(data) >= DATA_SIZE: break
                data.append(ord('a') + next_rand() % 26)
        else:
            if len(data) > 20:
                src = next_rand() % (len(data) - 1)
                l = 3 + next_rand() % 20
                for i in range(l):
                    if len(data) >= DATA_SIZE: break
                    dl = len(data)
                    data.append(data[src + (i % (dl - src))])
            else:
                data.append(ord('a') + next_rand() % 26)
    return bytes(data[:DATA_SIZE])

def lz77_compress(src):
    out = bytearray()
    sp = 0
    while sp < len(src):
        best_off = 0; best_len = 0
        win_start = max(0, sp - WINDOW_SIZE)
        for i in range(win_start, sp):
            l = 0
            max_len = min(len(src) - sp - 1, LOOKAHEAD)
            while l < max_len and src[i + l] == src[sp + l]: l += 1
            if l > best_len: best_len = l; best_off = sp - i
        if best_len >= 3:
            out.append(1)
            out.append((best_off >> 8) & 0xFF)
            out.append(best_off & 0xFF)
            out.append(best_len & 0xFF)
            sp += best_len
            if sp < len(src): out.append(src[sp]); sp += 1
            else: out.append(0)
        else:
            out.append(0)
            out.append(src[sp])
            sp += 1
    return bytes(out)

def lz77_decompress(src):
    out = bytearray()
    sp = 0
    while sp < len(src):
        if src[sp] == 1:
            sp += 1
            offset = (src[sp] << 8) | src[sp+1]; sp += 2
            length = src[sp]; sp += 1
            nxt = src[sp]; sp += 1
            start = len(out) - offset
            for i in range(length): out.append(out[start + i])
            out.append(nxt)
        else:
            sp += 1
            out.append(src[sp]); sp += 1
    return bytes(out)

rng_state = 42
data = generate_data()
t0 = time.monotonic()
compressed = lz77_compress(data)
decompressed = lz77_decompress(compressed)
verified = decompressed == data
ms = int((time.monotonic() - t0) * 1000)
print(f"original: {DATA_SIZE}")
print(f"compressed: {len(compressed)}")
print(f"ratio: {len(compressed) * 100 // DATA_SIZE}%")
print(f"verified: {'yes' if verified else 'no'}")
print(f"time: {ms} ms")
