limit = 1000000
sieve = Array.new(limit + 1, false)
i = 2
while i * i <= limit
  unless sieve[i]
    j = i * i
    while j <= limit
      sieve[j] = true
      j += i
    end
  end
  i += 1
end

count = 0
(2..limit).each do |i|
  count += 1 unless sieve[i]
end

puts count
