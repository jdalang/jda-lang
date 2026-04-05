#!/usr/bin/env python3
"""
jda-fuzz — Built-in fuzz testing for Jda

Discovers fn fuzz_* functions in .jda files, generates random inputs,
compiles once, and runs repeatedly to find crashes.

Fuzz target signature:
  fn fuzz_example(a: i64, b: i64) {
      ; test code here — crash (exit non-zero) means bug found
  }

Usage:
  jda-fuzz.sh <file.jda>                    Fuzz all fuzz_* functions
  jda-fuzz.sh --runs 10000 <file.jda>       Set iteration count (default: 1000)
  jda-fuzz.sh --time 30 <file.jda>          Run for N seconds
  jda-fuzz.sh --seed 42 <file.jda>          Reproducible random seed
  jda-fuzz.sh --corpus <dir> <file.jda>     Save/load crash corpus
  jda-fuzz.sh --workers 4 <file.jda>        Parallel fuzz workers

Crash corpus files are saved as one-line-per-arg text files.
Re-running with --corpus replays saved crashes as regression tests first.
"""

import sys
import os
import re
import random
import subprocess
import tempfile
import time
import signal
import struct

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
JDA = os.environ.get("JDA", os.path.join(PROJECT_ROOT, "bootstrap", "stage0", "jda1"))

# Interesting i64 values for mutations
INTERESTING_VALUES = [
    0, 1, -1, 2, -2,
    127, 128, -128, -129,
    255, 256, -256,
    32767, 32768, -32768, -32769,
    65535, 65536,
    2147483647, 2147483648, -2147483648, -2147483649,  # i32 bounds
    9223372036854775807, -9223372036854775808,  # i64 bounds
    0x5555555555555555, 0xAAAAAAAAAAAAAAAA,  # bit patterns
    0xDEADBEEF, 0xCAFEBABE,
]


def find_fuzz_targets(source):
    """Find fn fuzz_*(params) functions and extract parameter counts."""
    targets = []
    pattern = re.compile(r'^fn\s+(fuzz_\w+)\s*\(([^)]*)\)')
    for line in source.split('\n'):
        m = pattern.match(line.strip())
        if m:
            name = m.group(1)
            params_str = m.group(2).strip()
            if not params_str:
                param_count = 0
            else:
                param_count = len([p.strip() for p in params_str.split(',') if p.strip()])
            targets.append((name, param_count))
    return targets


def generate_wrapper(source, target_name, param_count):
    """Generate a main() wrapper that reads i64 values from stdin."""
    # Wrapper reads space-separated i64 values from stdin via syscall(0, 0, buf, n)
    wrapper = source + "\n"
    wrapper += """
fn fuzz_read_stdin(buf: &i8, max: i64) -> i64 {
    let n = syscall(0, 0, buf, max)
    if n < 0 { n = 0 }
    ret n
}

fn fuzz_parse_i64(buf: &i8, start: i64, out_end: &i64) -> i64 {
    let i = start
    ; skip whitespace
    loop buf[i] == 32 or buf[i] == 10 or buf[i] == 9 {
        i = i + 1
    }
    let neg: i64 = 0
    if buf[i] == 45 {
        neg = 1
        i = i + 1
    }
    let result: i64 = 0
    loop buf[i] >= 48 and buf[i] <= 57 {
        result = result * 10 + (buf[i] - 48)
        i = i + 1
    }
    if neg == 1 { result = 0 - result }
    out_end[0] = i
    ret result
}

fn main() {
    let buf = alloc_pages(1)
    let n = fuzz_read_stdin(buf, 4096)
    let pos = alloc_pages(1)
    pos[0] = 0
"""
    for i in range(param_count):
        wrapper += f"    let arg{i} = fuzz_parse_i64(buf, pos[0], pos)\n"

    args = ", ".join(f"arg{i}" for i in range(param_count))
    wrapper += f"    {target_name}({args})\n"
    wrapper += "}\n"
    return wrapper


def generate_input(param_count, rng):
    """Generate random i64 inputs using mutation strategies."""
    strategy = rng.randint(0, 4)
    values = []
    for _ in range(param_count):
        if strategy == 0:
            # Pure random
            values.append(rng.randint(-9223372036854775808, 9223372036854775807))
        elif strategy == 1:
            # Interesting values
            values.append(rng.choice(INTERESTING_VALUES))
        elif strategy == 2:
            # Small values (common edge cases)
            values.append(rng.randint(-100, 100))
        elif strategy == 3:
            # Powers of two +/- 1
            exp = rng.randint(0, 62)
            base = 1 << exp
            values.append(base + rng.choice([-1, 0, 1]))
        else:
            # Bit pattern mutations
            val = rng.getrandbits(64)
            if val >= (1 << 63):
                val -= (1 << 64)
            values.append(val)
    return values


def load_corpus(corpus_dir, target_name):
    """Load saved crash inputs from corpus directory."""
    inputs = []
    target_dir = os.path.join(corpus_dir, target_name)
    if not os.path.isdir(target_dir):
        return inputs
    for fname in sorted(os.listdir(target_dir)):
        fpath = os.path.join(target_dir, fname)
        if not os.path.isfile(fpath):
            continue
        try:
            with open(fpath, 'r') as f:
                values = [int(line.strip()) for line in f if line.strip()]
            inputs.append(values)
        except (ValueError, IOError):
            pass
    return inputs


def save_crash(corpus_dir, target_name, values, crash_num):
    """Save crashing input to corpus directory."""
    target_dir = os.path.join(corpus_dir, target_name)
    os.makedirs(target_dir, exist_ok=True)
    fname = os.path.join(target_dir, f"crash_{crash_num:04d}")
    with open(fname, 'w') as f:
        for v in values:
            f.write(f"{v}\n")
    return fname


def run_one(binary, values, timeout=5):
    """Run the fuzz binary with given inputs via stdin. Returns (ok, exit_code, stderr)."""
    stdin_data = " ".join(str(v) for v in values) + "\n"
    try:
        result = subprocess.run(
            [binary], timeout=timeout,
            input=stdin_data.encode(),
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE
        )
        return result.returncode == 0, result.returncode, result.stderr.decode('utf-8', errors='replace')
    except subprocess.TimeoutExpired:
        return False, -1, "TIMEOUT"
    except OSError as e:
        return False, -2, str(e)


def fuzz_target(source, target_name, param_count, args):
    """Fuzz a single target function."""
    max_runs = args.get('runs', 1000)
    max_time = args.get('time', 0)
    seed = args.get('seed', int(time.time() * 1000) & 0xFFFFFFFF)
    corpus_dir = args.get('corpus', None)
    workers = args.get('workers', 1)

    rng = random.Random(seed)

    # Generate wrapper source
    wrapper_src = generate_wrapper(source, target_name, param_count)

    # Compile
    with tempfile.NamedTemporaryFile(suffix='.jda', mode='w', delete=False) as f:
        f.write(wrapper_src)
        src_path = f.name

    bin_path = src_path.replace('.jda', '')
    try:
        result = subprocess.run(
            [JDA, src_path, bin_path],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        if result.returncode != 0:
            print(f"  FAIL  {target_name}: compile error")
            return 0, 0, 0
        os.chmod(bin_path, 0o755)
    except OSError as e:
        print(f"  FAIL  {target_name}: {e}")
        return 0, 0, 0

    crashes = []
    total_runs = 0
    start_time = time.time()

    # Phase 1: Replay corpus (regression tests)
    if corpus_dir:
        saved_inputs = load_corpus(corpus_dir, target_name)
        if saved_inputs:
            print(f"  {target_name}: replaying {len(saved_inputs)} corpus entries...")
            for values in saved_inputs:
                ok, code, stderr = run_one(bin_path, values)
                total_runs += 1
                if not ok:
                    crashes.append(values)
                    args_str = ", ".join(str(v) for v in values)
                    print(f"  CRASH (corpus replay) {target_name}({args_str}) exit={code}")

    # Phase 2: Random fuzzing
    print(f"  {target_name}: fuzzing with seed={seed}, params={param_count}...")

    run_count = 0
    last_report = start_time
    while True:
        # Check termination conditions
        if max_time > 0:
            if time.time() - start_time >= max_time:
                break
        else:
            if run_count >= max_runs:
                break

        values = generate_input(param_count, rng)
        ok, code, stderr = run_one(bin_path, values)
        run_count += 1
        total_runs += 1

        if not ok:
            crashes.append(values)
            args_str = ", ".join(str(v) for v in values)
            print(f"  CRASH #{len(crashes)} {target_name}({args_str}) exit={code}")
            if corpus_dir:
                fname = save_crash(corpus_dir, target_name, values, len(crashes))
                print(f"         saved to {fname}")

        # Progress report every 5 seconds
        now = time.time()
        if now - last_report >= 5.0:
            elapsed = now - start_time
            rate = total_runs / elapsed if elapsed > 0 else 0
            print(f"  {target_name}: {total_runs} runs, {len(crashes)} crashes, {rate:.0f} runs/sec")
            last_report = now

    # Cleanup
    os.unlink(src_path)
    if os.path.exists(bin_path):
        os.unlink(bin_path)

    elapsed = time.time() - start_time
    rate = total_runs / elapsed if elapsed > 0 else 0
    print(f"  {target_name}: {total_runs} runs in {elapsed:.1f}s ({rate:.0f}/sec), {len(crashes)} crashes")

    return total_runs, len(crashes), elapsed


def main():
    args = {
        'runs': 1000,
        'time': 0,
        'seed': None,
        'corpus': None,
        'workers': 1,
    }
    files = []

    i = 1
    while i < len(sys.argv):
        arg = sys.argv[i]
        if arg == '--runs' and i + 1 < len(sys.argv):
            args['runs'] = int(sys.argv[i + 1])
            i += 2
        elif arg == '--time' and i + 1 < len(sys.argv):
            args['time'] = int(sys.argv[i + 1])
            i += 2
        elif arg == '--seed' and i + 1 < len(sys.argv):
            args['seed'] = int(sys.argv[i + 1])
            i += 2
        elif arg == '--corpus' and i + 1 < len(sys.argv):
            args['corpus'] = sys.argv[i + 1]
            i += 2
        elif arg == '--workers' and i + 1 < len(sys.argv):
            args['workers'] = int(sys.argv[i + 1])
            i += 2
        elif arg in ('--help', '-h'):
            print(__doc__.strip())
            sys.exit(0)
        elif arg.startswith('-'):
            print(f"jda-fuzz: unknown option '{arg}'", file=sys.stderr)
            sys.exit(1)
        else:
            files.append(arg)
            i += 1
            continue
        continue

    if not files:
        print("usage: jda-fuzz.sh [options] <file.jda>", file=sys.stderr)
        sys.exit(1)

    if args['seed'] is None:
        args['seed'] = int(time.time() * 1000) & 0xFFFFFFFF

    total_runs = 0
    total_crashes = 0
    total_targets = 0

    for filepath in files:
        if os.path.isdir(filepath):
            jda_files = sorted(
                os.path.join(filepath, f)
                for f in os.listdir(filepath)
                if f.endswith('.jda')
            )
        else:
            jda_files = [filepath]

        for jda_file in jda_files:
            with open(jda_file, 'r') as f:
                source = f.read()

            targets = find_fuzz_targets(source)
            if not targets:
                continue

            print(f"\n=== {jda_file}: {len(targets)} fuzz target(s) ===")
            for target_name, param_count in targets:
                if param_count == 0:
                    print(f"  SKIP  {target_name}: no parameters to fuzz")
                    continue
                total_targets += 1
                runs, crashes, elapsed = fuzz_target(source, target_name, param_count, args)
                total_runs += runs
                total_crashes += crashes

    print(f"\n=== Fuzz Summary ===")
    print(f"  Targets: {total_targets}")
    print(f"  Runs:    {total_runs}")
    print(f"  Crashes: {total_crashes}")

    if total_crashes > 0:
        sys.exit(1)
    sys.exit(0)


if __name__ == '__main__':
    main()
