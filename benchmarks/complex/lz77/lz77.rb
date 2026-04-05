WINDOW_SIZE = 4096
LOOKAHEAD = 258
DATA_SIZE = 1024 * 1024

$rng = 42
def next_rand
  $rng = ($rng * 1103515245 + 12345) & 0x7FFFFFFF
  $rng
end

def generate_data
  data = []
  while data.length < DATA_SIZE
    r = next_rand
    rm = r % 3
    if rm == 0
      data << (97 + next_rand % 26)
    elsif rm == 1
      l = 1 + next_rand % 8
      l.times do
        break if data.length >= DATA_SIZE
        data << (97 + next_rand % 26)
      end
    else
      if data.length > 20
        src = next_rand % (data.length - 1)
        l = 3 + next_rand % 20
        l.times do |i|
          break if data.length >= DATA_SIZE
          dl = data.length
          data << data[src + (i % (dl - src))]
        end
      else
        data << (97 + next_rand % 26)
      end
    end
  end
  data[0, DATA_SIZE].pack("C*")
end

def lz77_compress(src)
  out = []
  sp = 0
  while sp < src.bytesize
    best_off = 0; best_len = 0
    win_start = [0, sp - WINDOW_SIZE].max
    i = win_start
    while i < sp
      l = 0
      max_len = [src.bytesize - sp - 1, LOOKAHEAD].min
      while l < max_len && src.getbyte(i + l) == src.getbyte(sp + l); l += 1; end
      if l > best_len; best_len = l; best_off = sp - i; end
      i += 1
    end
    if best_len >= 3
      out << 1 << ((best_off >> 8) & 0xFF) << (best_off & 0xFF) << (best_len & 0xFF)
      sp += best_len
      if sp < src.bytesize; out << src.getbyte(sp); sp += 1
      else; out << 0; end
    else
      out << 0 << src.getbyte(sp); sp += 1
    end
  end
  out.pack("C*")
end

def lz77_decompress(src)
  out = []
  sp = 0
  while sp < src.bytesize
    if src.getbyte(sp) == 1
      sp += 1
      offset = (src.getbyte(sp) << 8) | src.getbyte(sp+1); sp += 2
      length = src.getbyte(sp); sp += 1
      nxt = src.getbyte(sp); sp += 1
      start = out.length - offset
      length.times { |i| out << out[start + i] }
      out << nxt
    else
      sp += 1; out << src.getbyte(sp); sp += 1
    end
  end
  out.pack("C*")
end

$rng = 42
data = generate_data
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
compressed = lz77_compress(data)
decompressed = lz77_decompress(compressed)
verified = decompressed == data
ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).to_i
puts "original: #{DATA_SIZE}"
puts "compressed: #{compressed.bytesize}"
puts "ratio: #{compressed.bytesize * 100 / DATA_SIZE}%"
puts "verified: #{verified ? 'yes' : 'no'}"
puts "time: #{ms} ms"
