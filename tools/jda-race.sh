#!/usr/bin/env python3
"""
jda-race — Runtime data race detector for Jda concurrent programs

Detects data races: two threads access the same memory concurrently,
at least one is a write, and there is no synchronization between them.

Synchronization points that establish happens-before:
  - chan_send / chan_recv (channel operations)
  - atomic_store / atomic_load / atomic_cmpxchg / atomic_fetch_add
  - ctx_switch (cooperative yield — thread boundary)

Algorithm (epoch-based, simplified Lamport clocks):
  Each thread has a logical clock (epoch). Synchronization ops advance it.
  Each tracked variable stores the last-write epoch+tid and last-read epoch+tid.
  A race is: access from thread T at epoch E, but variable was last written by
  thread T' at epoch E', and there's no happens-before edge from E' to E.

  Simplified for cooperative J-Threads: since threads don't truly run in parallel
  (cooperative scheduling), we track "sync epochs" — every channel op or atomic
  bumps the epoch. Accesses to the same variable from different threads without
  an intervening sync on EITHER thread is a race.

Usage:
  jda-race.sh <file.jda>                   Run with race detection
  jda-race.sh --include <lib> <file.jda>   Include stdlib before instrumentation
  jda-race.sh --dry-run <file.jda>         Print instrumented source, don't run
"""

import sys
import os
import re
import subprocess
import tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
JDA = os.environ.get("JDA", os.path.join(PROJECT_ROOT, "bootstrap", "stage0", "jda1"))

# Race detection runtime
# Each variable tracked by a shadow entry: [last_write_tid, last_write_epoch,
#   last_read_tid, last_read_epoch]
# Each thread has a current epoch. Channel/atomic ops bump it (sync point).
# Race = access from different thread without intervening sync.
RACE_RUNTIME = r"""
; === Race Detection Runtime (happens-before) ===

; Shadow memory: per-variable tracking
; Layout per slot (4 i64s): [last_wr_tid, last_wr_epoch, last_rd_tid, last_rd_epoch]
let g_race_shadow: &i64 = 0
let g_race_shadow_cap: i64 = 0

; Per-thread state
let g_race_tid: i64 = 0
let g_race_epoch: i64 = 0
let g_race_next_tid: i64 = 1
let g_race_enabled: i64 = 0
let g_race_found: i64 = 0

; Sync epoch tracking: when a thread does a sync op, record (tid, epoch)
; Other threads that sync AFTER this can consider prior accesses as "before"
let g_race_sync_log: &i64 = 0
let g_race_sync_len: i64 = 0
let g_race_sync_cap: i64 = 0

fn race_init() {
    g_race_shadow = alloc_pages(64)
    g_race_shadow_cap = 8192
    g_race_sync_log = alloc_pages(16)
    g_race_sync_cap = 16384
    g_race_sync_len = 0
    g_race_tid = 0
    g_race_epoch = 1
    g_race_next_tid = 1
    g_race_enabled = 1
    g_race_found = 0
}

fn race_set_tid(tid: i64) {
    g_race_tid = tid
}

fn race_new_tid() -> i64 {
    let tid = g_race_next_tid
    g_race_next_tid = g_race_next_tid + 1
    ret tid
}

fn race_bump_epoch() {
    g_race_epoch = g_race_epoch + 1
}

; Record a synchronization event: current thread synced at current epoch.
; This means any future access on ANY thread that also syncs can see
; all prior writes from this thread.
fn race_sync() {
    if g_race_enabled == 0 { ret }
    race_bump_epoch()
    if g_race_sync_len < g_race_sync_cap {
        let sbase = g_race_sync_len * 2
        g_race_sync_log[sbase] = g_race_tid
        let sbase1 = sbase + 1
        g_race_sync_log[sbase1] = g_race_epoch
        g_race_sync_len = g_race_sync_len + 1
    }
}

; Check if there's a happens-before edge from (src_tid, src_epoch) to current thread.
; Returns 1 if synced (no race), 0 if no sync path (potential race).
; In cooperative scheduling: a sync happened if current thread did a sync op
; AFTER the source thread's access epoch.
fn race_has_hb(src_tid: i64, src_epoch: i64) -> i64 {
    if src_tid == g_race_tid { ret 1 }
    ; Check if there's any sync event from src_tid at or after src_epoch,
    ; followed by a sync on the current thread.
    let src_synced_at: i64 = 0
    let i = 0
    loop i < g_race_sync_len {
        let idx = i * 2
        let idx1 = idx + 1
        let st = g_race_sync_log[idx]
        let se = g_race_sync_log[idx1]
        if st == src_tid and se >= src_epoch {
            src_synced_at = se
        }
        i = i + 1
    }
    if src_synced_at == 0 { ret 0 }
    ; Check if current thread synced after src's sync
    let cur_synced = 0
    let j = 0
    loop j < g_race_sync_len {
        let jdx = j * 2
        let jdx1 = jdx + 1
        let st = g_race_sync_log[jdx]
        let se = g_race_sync_log[jdx1]
        if st == g_race_tid and se > src_synced_at {
            cur_synced = 1
        }
        j = j + 1
    }
    ret cur_synced
}

; Map variable hash to shadow slot index (0..cap-1)
fn race_slot(addr_hash: i64) -> i64 {
    let s = addr_hash
    if s < 0 { s = 0 - s }
    let q = s / g_race_shadow_cap
    let r = q * g_race_shadow_cap
    let slot = s - r
    ret slot
}

fn race_report(addr_hash: i64, cur_is_write: i64, other_tid: i64, other_is_write: i64) {
    g_race_found = g_race_found + 1
    print("==================")
    print("WARNING: DATA RACE")
    print("==================")
    if cur_is_write == 1 {
        print("Write by current thread (tid=")
    } else {
        print("Read by current thread (tid=")
    }
    print_int(g_race_tid)
    print(")")
    if other_is_write == 1 {
        print("Previous write by thread tid=")
    } else {
        print("Previous read by thread tid=")
    }
    print_int(other_tid)
    print("No synchronization between accesses")
    print("------------------")
}

fn race_track_write(addr_hash: i64) {
    if g_race_enabled == 0 { ret }
    let slot = race_slot(addr_hash)
    let base = slot * 4
    let prev_wr_tid = g_race_shadow[base]
    let prev_wr_epoch = g_race_shadow[base + 1]
    let prev_rd_tid = g_race_shadow[base + 2]
    let prev_rd_epoch = g_race_shadow[base + 3]

    ; Check write-write race: different thread wrote, no happens-before
    if prev_wr_epoch > 0 and prev_wr_tid != g_race_tid {
        let hb = race_has_hb(prev_wr_tid, prev_wr_epoch)
        if hb == 0 {
            race_report(addr_hash, 1, prev_wr_tid, 1)
        }
    }

    ; Check read-write race: different thread read, no happens-before
    if prev_rd_epoch > 0 and prev_rd_tid != g_race_tid {
        let hb = race_has_hb(prev_rd_tid, prev_rd_epoch)
        if hb == 0 {
            race_report(addr_hash, 1, prev_rd_tid, 0)
        }
    }

    ; Update shadow: record this write
    g_race_shadow[base] = g_race_tid
    g_race_shadow[base + 1] = g_race_epoch
}

fn race_track_read(addr_hash: i64) {
    if g_race_enabled == 0 { ret }
    let slot = race_slot(addr_hash)
    let base = slot * 4
    let prev_wr_tid = g_race_shadow[base]
    let prev_wr_epoch = g_race_shadow[base + 1]

    ; Check write-read race: different thread wrote, no happens-before
    if prev_wr_epoch > 0 and prev_wr_tid != g_race_tid {
        let hb = race_has_hb(prev_wr_tid, prev_wr_epoch)
        if hb == 0 {
            race_report(addr_hash, 0, prev_wr_tid, 1)
        }
    }

    ; Update shadow: record this read
    g_race_shadow[base + 2] = g_race_tid
    g_race_shadow[base + 3] = g_race_epoch
}

fn race_check() {
    if g_race_enabled == 0 { ret }
    g_race_enabled = 0
    if g_race_found > 0 {
        print("Found data race(s)")
        syscall(60, 66, 0, 0)
    }
}
"""


SCHED_GLOBALS = {
    'g_queue', 'g_head', 'g_tail', 'g_current', 'g_main_ctx',
}


def find_globals(source):
    """Find global let declarations (file-scope, before first fn).
    Excludes scheduler-internal globals and race runtime globals."""
    globals_set = set()
    in_function = False
    for line in source.split('\n'):
        stripped = line.strip()
        if stripped.startswith('fn '):
            in_function = True
        if not in_function:
            m = re.match(r'^let\s+(g_\w+)\s*[=:]', stripped)
            if m:
                name = m.group(1)
                if not name.startswith('g_race_') and name not in SCHED_GLOBALS:
                    globals_set.add(name)
    return globals_set


def hash_name(name):
    """Simple string hash for variable name -> address hash."""
    h = 5381
    for c in name:
        h = ((h * 33) + ord(c)) & 0x7FFFFFFFFFFFFFFF
    return h


# Channel and atomic builtins that count as synchronization
SYNC_BUILTINS = {
    'chan_send', 'chan_recv', 'chan_close',
    'atomic_load', 'atomic_store', 'atomic_cmpxchg', 'atomic_fetch_add',
}


def instrument_source(source, globals_set):
    """Instrument global accesses and sync points."""
    if not globals_set:
        return source

    name_hashes = {name: hash_name(name) for name in globals_set}

    lines = source.split('\n')
    instrumented = []
    in_function = False
    skip_race_fns = {
        'race_init', 'race_set_tid', 'race_new_tid', 'race_track',
        'race_track_read', 'race_track_write', 'race_check',
        'race_report', 'race_sync', 'race_bump_epoch', 'race_has_hb',
        'race_slot', 'race_stderr', 'race_stderr_int',
    }
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

        # Skip comments
        if stripped.startswith(';'):
            instrumented.append(line)
            continue

        # Don't instrument global declarations
        if re.match(r'^let\s+g_', stripped):
            instrumented.append(line)
            continue

        indent_m = re.match(r'^(\s*)', line)
        indent = indent_m.group(1) if indent_m else ""

        # Instrument synchronization builtins (channel/atomic ops)
        for builtin in SYNC_BUILTINS:
            if builtin + '(' in stripped:
                instrumented.append(f"{indent}race_sync()")
                break

        # Check for global variable writes: g_var = expr
        write_m = re.match(r'^(\s*)(g_\w+)\s*=\s', line)
        if write_m and write_m.group(2) in globals_set:
            gname = write_m.group(2)
            h = name_hashes[gname]
            instrumented.append(f"{indent}race_track_write({h})")
            instrumented.append(line)
            continue

        # Check for global variable reads in expressions
        read_globals = []
        for gname in globals_set:
            if re.search(r'\b' + re.escape(gname) + r'\b', stripped):
                if not re.match(r'^\s*' + re.escape(gname) + r'\s*=\s', line):
                    read_globals.append(gname)

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

        if re.match(r'^fn\s+main\s*\(', stripped):
            in_main = True
            main_found = True
            result.append(line)
            continue

        if in_main and main_found:
            if '{' in stripped or (result and result[-1].rstrip().endswith('{')):
                result.append("    race_init()")
                in_main = False

        # Inject race_check() before syscall(60, ...) exits
        if 'syscall(60,' in stripped:
            indent_m = re.match(r'^(\s*)', line)
            indent = indent_m.group(1) if indent_m else ""
            result.append(f"{indent}race_check()")

        result.append(line)

    return '\n'.join(result)


def inject_spawn_tid(source):
    """Instrument ctx_switch to bump TID at context switch points.

    ctx_switch is NOT synchronization — only channels/atomics are.
    We bump TID so accesses before/after ctx_switch are seen as different threads.
    """
    lines = source.split('\n')
    result = []
    # Skip scheduler-internal functions that use ctx_switch
    sched_fns = {'__thread_done', 'sched_yield'}
    current_fn = None
    ctx_counter = 0

    for line in lines:
        stripped = line.strip()

        fn_m = re.match(r'^fn\s+(\w+)', stripped)
        if fn_m:
            current_fn = fn_m.group(1)

        # Only instrument ctx_switch in non-scheduler user functions
        if ('ctx_switch(' in stripped and not stripped.startswith(';')
                and current_fn not in sched_fns):
            indent_m = re.match(r'^(\s*)', line)
            indent = indent_m.group(1) if indent_m else ""
            vname = f"_rtid{ctx_counter}"
            ctx_counter += 1
            result.append(f"{indent}let {vname} = g_race_tid")
            result.append(f"{indent}race_set_tid(race_new_tid())")
            result.append(line)
            result.append(f"{indent}race_set_tid({vname})")
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

    with open(files[0], 'r') as f:
        source = f.read()

    include_source = ""
    if include_path:
        with open(include_path, 'r') as f:
            include_source = f.read()

    full_source = include_source + "\n" + source if include_source else source
    globals_set = find_globals(full_source)

    if not globals_set:
        print("jda-race: no g_* global variables found to track", file=sys.stderr)
        print("Race detector tracks variables with g_ prefix (e.g., let g_counter = 0)", file=sys.stderr)
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

    instrumented = RACE_RUNTIME + "\n"
    if include_source:
        instrumented += include_source + "\n"

    user_instrumented = instrument_source(source, globals_set)
    user_instrumented = inject_spawn_tid(user_instrumented)
    user_instrumented = inject_race_init(user_instrumented)
    instrumented += user_instrumented

    if dry_run:
        print(instrumented)
        sys.exit(0)

    with tempfile.NamedTemporaryFile(suffix='.jda', mode='w', delete=False) as f:
        f.write(instrumented)
        src_path = f.name

    bin_path = src_path.replace('.jda', '')
    try:
        result = subprocess.run([JDA, src_path, bin_path],
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        if result.returncode != 0:
            stderr_text = result.stderr.decode('utf-8', errors='replace')
            print(f"jda-race: compilation failed", file=sys.stderr)
            if stderr_text:
                print(stderr_text, file=sys.stderr)
            sys.exit(1)
        os.chmod(bin_path, 0o755)

        result = subprocess.run([bin_path])
        sys.exit(result.returncode)
    finally:
        os.unlink(src_path)
        if os.path.exists(bin_path):
            os.unlink(bin_path)


if __name__ == '__main__':
    main()
