N = 2_000_000
$rng = 42
def lcg; $rng = ($rng * 1103515245 + 12345) & 2147483647; $rng end

arr = Array.new(N) { lcg }
tmp = Array.new(N, 0)

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
w = 1
while w < N
  lo = 0
  while lo < N
    mid = [lo + w, N].min
    hi  = [lo + 2*w, N].min
    if mid < hi
      i, j, k = lo, mid, lo
      while k < hi
        if i < mid && (j >= hi || arr[i] <= arr[j])
          tmp[k] = arr[i]; i += 1
        else
          tmp[k] = arr[j]; j += 1
        end
        k += 1
      end
      arr[lo...hi] = tmp[lo...hi]
    end
    lo += 2*w
  end
  w *= 2
end
ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).to_i
ok = (1...N).all? { |i| arr[i-1] <= arr[i] } ? 1 : 0
chk = arr.sum & 0xffffffff
puts "n: #{N}\nsorted: #{ok}\nfirst: #{arr[0]}\nlast: #{arr[-1]}\nchecksum: #{chk}\ntime: #{ms} ms"
