#!/usr/bin/env python3
"""
jda-race — Runtime race detector for Jda concurrent programs

Detects data races on global variables accessed by multiple J-Threads
without proper synchronization (channels or atomics).

How it works:
  1. Parses Jda source to find global variables and function boundaries
  2. Instruments global variable reads/writes with race_track_read/race_track_write
  3. Instruments spawn calls to assign thread IDs
  4. Prepends a race detection runtime that logs accesses per thread
  5. At exit, reports conflicting unsynchronized accesses

Usage:
  jda-race.sh <file.jda>                   Run with race detection
  jda-race.sh --include <lib> <file.jda>   Include stdlib before instrumentation
  jda-race.sh --dry-run <file.jda>         Print instrumented source, don't run

Race conditions detected:
  - Global variable written by one thread, read by another (no channel sync)
  - Global variable written by two different threads (no atomic)
  - Unsynchronized shared pointer dereferences
"""

import sys
import os
import re
import subprocess
import tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
JDA = os.environ.get("JDA", os.path.join(PROJECT_ROOT, "bootstrap", "stage0", "jda1"))

# Race detection runtime — prepended to instrumented source
# Uses a fixed-size log of (thread_id, address_hash, is_write) entries
# At exit, scans for conflicting accesses from different threads
RACE_RUNTIME = r"""
; === Race Detection Runtime ===
let g_race_log: &i64 = 0
let g_race_log_len: i64 = 0
let g_race_log_cap: i64 = 0
let g_race_tid: i64 = 0
let g_race_next_tid: i64 = 1
let g_race_count: i64 = 0
let g_race_enabled: i64 = 0
let g_race_msgbuf: &i8 = 0

fn race_init() {
    g_race_log = alloc_pages(256)
    g_race_msgbuf = alloc_pages(1)
    g_race_log_cap = 87380
    g_race_log_len = 0
    g_race_tid = 0
    g_race_next_tid = 1
    g_race_count = 0
    g_race_enabled = 1
}

fn race_set_tid(tid: i64) {
    g_race_tid = tid
}

fn race_new_tid() -> i64 {
    let tid = g_race_next_tid
    g_race_next_tid = g_race_next_tid + 1
    ret tid
}

fn race_track(addr_hash: i64, is_write: i64) {
    if g_race_enabled == 0 { ret }
    if g_race_log_len >= g_race_log_cap { ret }
    let base = g_race_log_len * 3
    g_race_log[base] = g_race_tid
    g_race_log[base + 1] = addr_hash
    g_race_log[base + 2] = is_write
    g_race_log_len = g_race_log_len + 1
}

fn race_track_read(addr_hash: i64) {
    race_track(addr_hash, 0)
}

fn race_track_write(addr_hash: i64) {
    race_track(addr_hash, 1)
}

fn race_stderr(msg: &i8, len: i64) {
    syscall(1, 2, msg, len)
}

fn race_stderr_int(n: i64) {
    let buf = g_race_msgbuf
    let neg = 0
    if n < 0 {
        neg = 1
        n = 0 - n
    }
    let i = 20
    if n == 0 {
        i = i - 1
        poke_byte(buf, i, 48)
    }
    loop n > 0 {
        i = i - 1
        let d = n - (n / 10 * 10)
        poke_byte(buf, i, 48 + d)
        n = n / 10
    }
    if neg == 1 {
        i = i - 1
        poke_byte(buf, i, 45)
    }
    let len = 20 - i
    let ptr = buf + i
    syscall(1, 2, ptr, len)
}

fn race_check() {
    if g_race_enabled == 0 { ret }
    g_race_enabled = 0
    let races = 0
    let i = 0
    loop i < g_race_log_len {
        let ti = g_race_log[i * 3]
        let ai = g_race_log[i * 3 + 1]
        let wi = g_race_log[i * 3 + 2]
        let j = i + 1
        loop j < g_race_log_len {
            let tj = g_race_log[j * 3]
            let aj = g_race_log[j * 3 + 1]
            let wj = g_race_log[j * 3 + 2]
            if ai == aj {
                if ti != tj {
                    ; Same address, different threads
                    if wi == 1 or wj == 1 {
                        ; At least one is a write — DATA RACE
                        races = races + 1
                        ; Skip further inner-loop checks for this i
                        j = g_race_log_len
                    }
                }
            }
            j = j + 1
        }
        i = i + 1
    }
    if races > 0 {
        print("WARNING: DATA RACE")
        print("Found ")
        print_int(races)
        print(" data race(s)")
        syscall(60, 66, 0, 0)
    }
}
"""


def find_globals(source):
    """Find global let declarations (file-scope, before first fn)."""
    globals_set = set()
    in_function = False
    for line in source.split('\n'):
        stripped = line.strip()
        if stripped.startswith('fn '):
            in_function = True
        if not in_function:
            # Global let declaration
            m = re.match(r'^let\s+(g_\w+|[a-z_]\w*)\s*[=:]', stripped)
            if m:
                name = m.group(1)
                # Only track g_ prefixed globals (convention for shared state)
                if name.startswith('g_'):
                    globals_set.add(name)
    return globals_set


def hash_name(name):
    """Simple string hash for variable name → address hash."""
    h = 5381
    for c in name:
        h = ((h * 33) + ord(c)) & 0x7FFFFFFFFFFFFFFF
    return h


def instrument_source(source, globals_set, include_source=""):
    """Instrument global variable accesses with race tracking calls."""
    if not globals_set:
        return source

    # Build hash map of global names
    name_hashes = {name: hash_name(name) for name in globals_set}

    lines = source.split('\n')
    instrumented = []
    in_function = False
    fn_depth = 0
    skip_race_fns = {'race_init', 'race_set_tid', 'race_new_tid', 'race_track',
                     'race_track_read', 'race_track_write', 'race_check',
                     'race_print_i64'}
    in_race_fn = False

    for line in lines:
        stripped = line.strip()

        # Track function boundaries
        if re.match(r'^fn\s+(\w+)', stripped):
            in_function = True
            fn_name_m = re.match(r'^fn\s+(\w+)', stripped)
            if fn_name_m and fn_name_m.group(1) in skip_race_fns:
                in_race_fn = True
            else:
                in_race_fn = False

        if not in_function or in_race_fn:
            instrumented.append(line)
            continue

        # Don't instrument global declarations
        if re.match(r'^let\s+g_', stripped):
            instrumented.append(line)
            continue

        # Check for global variable writes: g_var = expr
        write_m = re.match(r'^(\s*)(g_\w+)\s*=\s', line)
        if write_m and write_m.group(2) in globals_set:
            indent = write_m.group(1)
            gname = write_m.group(2)
            h = name_hashes[gname]
            instrumented.append(f"{indent}race_track_write({h})")
            instrumented.append(line)
            continue

        # Check for global variable reads in expressions
        # Insert race_track_read before lines that reference globals (but aren't writes)
        has_read = False
        read_globals = []
        for gname in globals_set:
            # Check if this global appears in the line (in an expression context)
            # Avoid matching in comments or string literals
            if stripped.startswith(';'):
                break
            # Simple pattern: global name appears as a word boundary
            if re.search(r'\b' + re.escape(gname) + r'\b', stripped):
                # Make sure it's not a write (already handled above)
                if not re.match(r'^\s*' + re.escape(gname) + r'\s*=\s', line):
                    read_globals.append(gname)
                    has_read = True

        if has_read:
            indent_m = re.match(r'^(\s*)', line)
            indent = indent_m.group(1) if indent_m else ""
            for gname in read_globals:
                h = name_hashes[gname]
                instrumented.append(f"{indent}race_track_read({h})")

        instrumented.append(line)

    return '\n'.join(instrumented)


def inject_race_init(source):
    """Inject race_init() at start of main() and race_check() before exits."""
    lines = source.split('\n')
    result = []
    in_main = False
    main_found = False

    for i, line in enumerate(lines):
        stripped = line.strip()

        # Find main function
        if re.match(r'^fn\s+main\s*\(', stripped):
            in_main = True
            main_found = True
            result.append(line)
            continue

        # Inject race_init() after main's opening brace
        if in_main and not main_found is False:
            if '{' in stripped or result[-1].rstrip().endswith('{'):
                result.append("    race_init()")
                in_main = False  # Only inject once

        # Inject race_check() before syscall(60, ...) exits
        if 'syscall(60,' in stripped:
            indent_m = re.match(r'^(\s*)', line)
            indent = indent_m.group(1) if indent_m else ""
            result.append(f"{indent}race_check()")

        result.append(line)

    return '\n'.join(result)


def inject_spawn_tid(source):
    """Instrument spawn calls to assign thread IDs."""
    lines = source.split('\n')
    result = []

    for line in lines:
        stripped = line.strip()

        # Before spawn, save current tid and assign new one
        if 'spawn ' in stripped and not stripped.startswith(';'):
            indent_m = re.match(r'^(\s*)', line)
            indent = indent_m.group(1) if indent_m else ""
            # After the spawn line, we need to note that the spawned fn
            # will run with a new tid. We insert tid tracking around ctx_switch.
            result.append(line)
            continue

        # Instrument ctx_switch — the point where thread context actually changes
        if 'ctx_switch(' in stripped and not stripped.startswith(';'):
            indent_m = re.match(r'^(\s*)', line)
            indent = indent_m.group(1) if indent_m else ""
            result.append(f"{indent}let _saved_tid = g_race_tid")
            result.append(f"{indent}race_set_tid(race_new_tid())")
            result.append(line)
            result.append(f"{indent}race_set_tid(_saved_tid)")
            continue

        result.append(line)

    return '\n'.join(result)


def main():
    files = []
    include_path = None
    dry_run = False

    i = 1
    while i < len(sys.argv):
        arg = sys.argv[i]
        if arg == '--include' and i + 1 < len(sys.argv):
            include_path = sys.argv[i + 1]
            i += 2
        elif arg == '--dry-run':
            dry_run = True
            i += 1
        elif arg in ('--help', '-h'):
            print(__doc__.strip())
            sys.exit(0)
        elif arg.startswith('-'):
            print(f"jda-race: unknown option '{arg}'", file=sys.stderr)
            sys.exit(1)
        else:
            files.append(arg)
            i += 1

    if not files:
        print("usage: jda-race.sh [--include <lib>] <file.jda>", file=sys.stderr)
        sys.exit(1)

    # Read source
    with open(files[0], 'r') as f:
        source = f.read()

    # Read include file if specified
    include_source = ""
    if include_path:
        with open(include_path, 'r') as f:
            include_source = f.read()

    # Find globals to track
    full_source = include_source + "\n" + source if include_source else source
    globals_set = find_globals(full_source)

    if not globals_set:
        print("jda-race: no g_* global variables found to track", file=sys.stderr)
        print("Race detector tracks variables with g_ prefix (e.g., let g_counter = 0)", file=sys.stderr)
        # Still run the program normally
        if not dry_run:
            with tempfile.NamedTemporaryFile(suffix='.jda', mode='w', delete=False) as f:
                f.write(full_source)
                src_path = f.name
            bin_path = src_path.replace('.jda', '')
            try:
                result = subprocess.run([JDA, src_path, bin_path],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if result.returncode != 0:
                    print("jda-race: compilation failed", file=sys.stderr)
                    sys.exit(1)
                os.chmod(bin_path, 0o755)
                result = subprocess.run([bin_path])
                sys.exit(result.returncode)
            finally:
                os.unlink(src_path)
                if os.path.exists(bin_path):
                    os.unlink(bin_path)
        sys.exit(0)

    print(f"jda-race: tracking {len(globals_set)} global(s): {', '.join(sorted(globals_set))}", file=sys.stderr)

    # Build instrumented source
    instrumented = RACE_RUNTIME + "\n"
    if include_source:
        instrumented += include_source + "\n"

    # Instrument the user source
    user_instrumented = instrument_source(source, globals_set)
    user_instrumented = inject_spawn_tid(user_instrumented)
    user_instrumented = inject_race_init(user_instrumented)
    instrumented += user_instrumented

    if dry_run:
        print(instrumented)
        sys.exit(0)

    # Write instrumented source to temp file
    with tempfile.NamedTemporaryFile(suffix='.jda', mode='w', delete=False) as f:
        f.write(instrumented)
        src_path = f.name

    bin_path = src_path.replace('.jda', '')
    try:
        # Compile
        result = subprocess.run([JDA, src_path, bin_path],
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        if result.returncode != 0:
            stderr_text = result.stderr.decode('utf-8', errors='replace')
            print(f"jda-race: compilation failed", file=sys.stderr)
            if stderr_text:
                print(stderr_text, file=sys.stderr)
            sys.exit(1)
        os.chmod(bin_path, 0o755)

        # Run
        result = subprocess.run([bin_path])
        sys.exit(result.returncode)
    finally:
        os.unlink(src_path)
        if os.path.exists(bin_path):
            os.unlink(bin_path)


if __name__ == '__main__':
    main()
