N = 256
a = Array.new(N){|i| Array.new(N){|j| (i*7+j*13+1)%100}}
b = Array.new(N){|i| Array.new(N){|j| (i*11+j*5+3)%100}}
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
c = Array.new(N){|i| Array.new(N){|j| (0...N).sum{|k| a[i][k]*b[k][j]}}}
ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC)-t0)*1000).to_i
chk = c.sum{|row| row.sum} % 1000000007
puts "n: #{N}\nchecksum: #{chk}\ntime: #{ms} ms"
