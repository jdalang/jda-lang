limit = 1000000
sieve = [False] * (limit + 1)
i = 2
while i * i <= limit:
    if not sieve[i]:
        j = i * i
        while j <= limit:
            sieve[j] = True
            j += i
    i += 1

count = 0
for i in range(2, limit + 1):
    if not sieve[i]:
        count += 1

print(count)
