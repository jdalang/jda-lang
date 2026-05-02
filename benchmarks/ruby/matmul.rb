N = 200

a = Array.new(N * N, 0)
b = Array.new(N * N, 0)
c = Array.new(N * N, 0)

N.times do |i|
  N.times do |j|
    a[i * N + j] = i + j
    b[i * N + j] = i * j + 1
  end
end

N.times do |i|
  N.times do |j|
    s = 0
    N.times do |k|
      s += a[i * N + k] * b[k * N + j]
    end
    c[i * N + j] = s
  end
end

puts c[99 * N + 99]
