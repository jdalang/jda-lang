MAX_STATES = 2048
# c: >=0 literal, -1 ANY, -2 SPLIT, -3 MATCH, -4 EPSILON
$nfa = []
$nstates = 0
$start_state = 0

def new_state(c, out1, out2)
  s = $nstates; $nstates += 1
  $nfa << [c, out1, out2]
  s
end

class REParser
  def initialize(pat); @pat = pat; @pos = 0; end
  def peek; @pos < @pat.length ? @pat[@pos].ord : 0; end
  def adv; @pos += 1 if @pos < @pat.length; end

  def parse_atom
    c = peek
    if c == 40; adv; f = parse_expr; adv if peek == 41; return f; end
    if c == 46
      adv; s = new_state(-1, -1, -1); j = new_state(-4, -1, -1)
      $nfa[s][1] = j; return [s, j]
    end
    adv; s = new_state(c, -1, -1); j = new_state(-4, -1, -1)
    $nfa[s][1] = j; [s, j]
  end

  def parse_factor
    fs, fe = parse_atom; c = peek
    if c == 42  # *
      adv; sp = new_state(-2, fs, -1); j = new_state(-4, -1, -1)
      $nfa[fe][1] = sp; $nfa[sp][2] = j; return [sp, j]
    end
    if c == 43  # +
      adv; sp = new_state(-2, fs, -1); j = new_state(-4, -1, -1)
      $nfa[fe][1] = sp; $nfa[sp][2] = j; return [fs, j]
    end
    if c == 63  # ?
      adv; sp = new_state(-2, fs, -1); j = new_state(-4, -1, -1)
      $nfa[fe][1] = j; $nfa[sp][2] = j; return [sp, j]
    end
    [fs, fe]
  end

  def parse_term
    fs, fe = parse_factor
    while peek != 0 && peek != 41 && peek != 124
      s2, e2 = parse_factor
      $nfa[fe][1] = s2; fe = e2
    end
    [fs, fe]
  end

  def parse_expr
    fs, fe = parse_term
    while peek == 124
      adv; s2, e2 = parse_term
      s = new_state(-2, fs, s2); j = new_state(-4, -1, -1)
      $nfa[fe][1] = j; $nfa[e2][1] = j
      fs, fe = s, j
    end
    [fs, fe]
  end
end

def compile_regex(pattern)
  $nfa = []; $nstates = 0
  p = REParser.new(pattern)
  fs, fe = p.parse_expr
  accept = new_state(-3, -1, -1)
  $nfa[fe][1] = accept
  $start_state = fs
end

$seen = Array.new(MAX_STATES, 0)
$gen = 0

def add_state(list, s)
  return if s < 0 || s >= $nstates
  return if $seen[s] == $gen
  $seen[s] = $gen
  if $nfa[s][0] == -2; add_state(list, $nfa[s][1]); add_state(list, $nfa[s][2]); return; end
  if $nfa[s][0] == -4; add_state(list, $nfa[s][1]); return; end
  list << s
end

def match_nfa(str)
  $gen += 1; clist = []; add_state(clist, $start_state)
  str.each_byte do |ch|
    $gen += 1; nlist = []
    clist.each do |st|
      if $nfa[st][0] == ch || $nfa[st][0] == -1
        add_state(nlist, $nfa[st][1])
      end
    end
    clist = nlist
    return false if clist.empty?
  end
  clist.any? { |st| $nfa[st][0] == -3 }
end

def gen_string(seed, len)
  rng = (seed * 2654435761 + 1) & 0x7FFFFFFF
  (0...len).map { |i|
    rng = (rng * 1103515245 + 12345 + seed) & 0x7FFFFFFF
    (97 + rng % 26).chr
  }.join
end

patterns = [
  "a.*b.*c", "(ab|cd|ef)+", "a.b.c.d.e", "(a|b)(c|d)(e|f)",
  "ab*c+d?ef", ".*hello.*world.*", "(abc|def|ghi|jkl)+", "a.*a.*a.*a",
]
nstrings = 100000
total_matches = 0
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
patterns.each_with_index do |pat, p_idx|
  compile_regex(pat)
  matches = 0
  nstrings.times do |i|
    ln = 10 + (i % 50)
    s = gen_string(i + p_idx * 1000, ln)
    matches += 1 if match_nfa(s)
  end
  total_matches += matches
end
ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).to_i
puts "matches: #{total_matches}"
puts "time: #{ms} ms"
