#!/bin/bash
# jda-race — Runtime data race detector for Jda concurrent programs
#
# Detects data races: two threads access the same memory concurrently,
# at least one is a write, and there is no synchronization between them.
#
# Synchronization points that establish happens-before:
#   - chan_send / chan_recv / chan_close (channel operations)
#   - atomic_store / atomic_load / atomic_cmpxchg / atomic_fetch_add
#
# Algorithm (epoch-based, simplified Lamport clocks):
#   Each thread has a logical clock (epoch). Sync ops advance it.
#   Each tracked variable stores last-write epoch+tid and last-read epoch+tid.
#   Race = access from different thread without happens-before edge.
#
# Usage:
#   jda-race.sh <file.jda>                   Run with race detection
#   jda-race.sh --include <lib> <file.jda>   Include stdlib before instrumentation
#   jda-race.sh --dry-run <file.jda>         Print instrumented source, don't run

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JDA="${JDA:-$SCRIPT_DIR/../bootstrap/stage0/jda1}"
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# --- Parse arguments ---
INCLUDE_PATH=""
DRY_RUN=0
FILES=()

while [ $# -gt 0 ]; do
    case "$1" in
        --include) INCLUDE_PATH="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help)
            sed -n '2,/^$/s/^# \?//p' "$0"
            exit 0
            ;;
        -*) echo "jda-race: unknown option '$1'" >&2; exit 1 ;;
        *)  FILES+=("$1"); shift ;;
    esac
done

if [ ${#FILES[@]} -eq 0 ]; then
    echo "usage: jda-race.sh [--include <lib>] <file.jda>" >&2
    exit 1
fi

SOURCE_FILE="${FILES[0]}"

# --- Race detection runtime (Jda source, prepended to instrumented file) ---
RACE_RUNTIME='; === Race Detection Runtime (happens-before) ===

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

fn race_has_hb(src_tid: i64, src_epoch: i64) -> i64 {
    if src_tid == g_race_tid { ret 1 }
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

    if prev_wr_epoch > 0 and prev_wr_tid != g_race_tid {
        let hb = race_has_hb(prev_wr_tid, prev_wr_epoch)
        if hb == 0 {
            race_report(addr_hash, 1, prev_wr_tid, 1)
        }
    }

    if prev_rd_epoch > 0 and prev_rd_tid != g_race_tid {
        let hb = race_has_hb(prev_rd_tid, prev_rd_epoch)
        if hb == 0 {
            race_report(addr_hash, 1, prev_rd_tid, 0)
        }
    }

    g_race_shadow[base] = g_race_tid
    g_race_shadow[base + 1] = g_race_epoch
}

fn race_track_read(addr_hash: i64) {
    if g_race_enabled == 0 { ret }
    let slot = race_slot(addr_hash)
    let base = slot * 4
    let prev_wr_tid = g_race_shadow[base]
    let prev_wr_epoch = g_race_shadow[base + 1]

    if prev_wr_epoch > 0 and prev_wr_tid != g_race_tid {
        let hb = race_has_hb(prev_wr_tid, prev_wr_epoch)
        if hb == 0 {
            race_report(addr_hash, 0, prev_wr_tid, 1)
        }
    }

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
'

# --- djb2 hash in bash (same algorithm as before, fits in 63-bit) ---
hash_name() {
    local name="$1"
    local h=5381
    local i
    for (( i=0; i<${#name}; i++ )); do
        local c
        c=$(printf '%d' "'${name:$i:1}")
        h=$(( (h * 33 + c) & 0x7FFFFFFFFFFFFFFF ))
    done
    echo "$h"
}

# --- Find user globals (g_* at file scope, exclude scheduler/race internals) ---
find_globals() {
    local file="$1"
    # Globals are "let g_..." lines before the first "fn " line
    # Extract name: "let g_foo = ..." or "let g_foo: ..." → "g_foo"
    awk '
        /^fn / { exit }
        /^let g_/ {
            s = $0
            sub(/^let /, "", s)
            # Get the identifier (stop at space, =, :)
            gsub(/[^a-zA-Z0-9_].*/, "", s)
            name = s
            if (name ~ /^g_race_/) next
            if (name == "g_queue" || name == "g_head" || name == "g_tail" || \
                name == "g_current" || name == "g_main_ctx") next
            print name
        }
    ' "$file"
}

# --- Main instrumentation via awk ---
# Reads source; globals/hashes embedded via dynamic BEGIN block
instrument() {
    local source_file="$1"
    local globals_file="$2"
    local hashes_file="$3"

    # Build awk BEGIN block that embeds globals and hashes directly
    local awk_init=""
    while IFS= read -r gname; do
        awk_init="${awk_init}globals[\"${gname}\"]=1; nglob++; "
    done < "$globals_file"
    while IFS=' ' read -r gname ghval; do
        awk_init="${awk_init}ghash[\"${gname}\"]=\"${ghval}\"; "
    done < "$hashes_file"

    awk '
    BEGIN {
        '"$awk_init"'

        in_function = 0
        in_race_fn = 0
        current_fn = ""
        ctx_counter = 0

        # Race runtime internal functions — skip instrumentation inside these
        skip_fn["race_init"] = 1
        skip_fn["race_set_tid"] = 1
        skip_fn["race_new_tid"] = 1
        skip_fn["race_bump_epoch"] = 1
        skip_fn["race_sync"] = 1
        skip_fn["race_has_hb"] = 1
        skip_fn["race_slot"] = 1
        skip_fn["race_report"] = 1
        skip_fn["race_track_write"] = 1
        skip_fn["race_track_read"] = 1
        skip_fn["race_check"] = 1

        # Scheduler functions — skip ctx_switch instrumentation
        sched_fn["__thread_done"] = 1
        sched_fn["sched_yield"] = 1

        # Sync builtins
        sync_bi["chan_send("] = 1
        sync_bi["chan_recv("] = 1
        sync_bi["chan_close("] = 1
        sync_bi["atomic_load("] = 1
        sync_bi["atomic_store("] = 1
        sync_bi["atomic_cmpxchg("] = 1
        sync_bi["atomic_fetch_add("] = 1

        main_next_line = 0
    }

    # Track function boundaries
    /^fn [a-zA-Z_]/ {
        in_function = 1
        s = $0
        sub(/^fn /, "", s)
        gsub(/[^a-zA-Z0-9_].*/, "", s)
        current_fn = s
        in_race_fn = (current_fn in skip_fn) ? 1 : 0
    }

    # Inject race_init() after fn main() {
    /^fn main\(/ {
        print
        # If { is on this line, inject race_init() right after
        if (index($0, "{") > 0) {
            print "    race_init()"
        } else {
            main_next_line = 1
        }
        next
    }
    main_next_line == 1 && /\{/ {
        main_next_line = 0
        print
        print "    race_init()"
        next
    }

    # Not in function or in race fn — pass through
    (in_function == 0 || in_race_fn == 1) { print; next }

    # Comments — pass through
    /^[[:space:]]*;/ { print; next }

    # Global declarations — pass through
    /^let g_/ { print; next }

    {
        line = $0
        stripped = line
        gsub(/^[[:space:]]+/, "", stripped)

        # Get indentation
        match(line, /^[[:space:]]*/)
        indent = substr(line, RSTART, RLENGTH)

        # --- ctx_switch instrumentation (TID change, NOT sync) ---
        if (index(stripped, "ctx_switch(") > 0 && substr(stripped,1,1) != ";" && \
            !(current_fn in sched_fn)) {
            vname = "_rtid" ctx_counter
            ctx_counter++
            print indent "let " vname " = g_race_tid"
            print indent "race_set_tid(race_new_tid())"
            print line
            print indent "race_set_tid(" vname ")"
            next
        }

        # --- Inject race_check() before syscall(60,...) ---
        if (index(stripped, "syscall(60,") > 0) {
            print indent "race_check()"
        }

        # --- Sync builtins (channel/atomic ops) ---
        for (bi in sync_bi) {
            if (index(stripped, bi) > 0) {
                print indent "race_sync()"
                break
            }
        }

        # --- Global write: "g_var = expr" (not "g_var == expr") ---
        is_write = 0
        write_gname = ""
        if (match(stripped, /^g_[a-zA-Z0-9_]+[[:space:]]*=[^=]/)) {
            wtemp = stripped
            gsub(/[^a-zA-Z0-9_].*/, "", wtemp)
            write_gname = wtemp
            if (write_gname in globals) {
                is_write = 1
                print indent "race_track_write(" ghash[write_gname] ")"
                print line
                next
            }
        }

        # --- Global reads in expressions ---
        for (gn in globals) {
            # Check if this global appears in the line (word boundary via regex)
            pat = "(^|[^a-zA-Z0-9_])" gn "([^a-zA-Z0-9_]|$)"
            if (match(stripped, pat)) {
                # Make sure it is not a write (already handled above)
                wcheck = "^" gn "[[:space:]]*=[^=]"
                if (!match(stripped, wcheck)) {
                    print indent "race_track_read(" ghash[gn] ")"
                }
            }
        }

        print line
    }
    ' "$source_file"
}

# --- Build full source and find globals ---
FULL_SOURCE="$TMP_DIR/full.jda"
if [ -n "$INCLUDE_PATH" ]; then
    cat "$INCLUDE_PATH" > "$FULL_SOURCE"
    echo "" >> "$FULL_SOURCE"
    cat "$SOURCE_FILE" >> "$FULL_SOURCE"
else
    cat "$SOURCE_FILE" > "$FULL_SOURCE"
fi

GLOBALS_FILE="$TMP_DIR/globals.txt"
find_globals "$FULL_SOURCE" > "$GLOBALS_FILE"
NGLOBALS=$(wc -l < "$GLOBALS_FILE" | tr -d ' ')

if [ "$NGLOBALS" -eq 0 ]; then
    echo "jda-race: no g_* global variables found to track" >&2
    echo "Race detector tracks variables with g_ prefix (e.g., let g_counter = 0)" >&2
    if [ "$DRY_RUN" -eq 1 ]; then
        cat "$FULL_SOURCE"
        exit 0
    fi
    "$JDA" "$FULL_SOURCE" "$TMP_DIR/out" >/dev/null 2>/dev/null
    chmod +x "$TMP_DIR/out"
    exec "$TMP_DIR/out"
fi

# Compute hashes
HASHES_FILE="$TMP_DIR/hashes.txt"
while IFS= read -r gname; do
    h=$(hash_name "$gname")
    echo "$gname $h"
done < "$GLOBALS_FILE" > "$HASHES_FILE"

GLIST=$(paste -sd', ' "$GLOBALS_FILE")
echo "jda-race: tracking $NGLOBALS global(s): $GLIST" >&2

# --- Generate instrumented source ---
INSTR_FILE="$TMP_DIR/instrumented.jda"
{
    echo "$RACE_RUNTIME"
    echo ""
    if [ -n "$INCLUDE_PATH" ]; then
        cat "$INCLUDE_PATH"
        echo ""
    fi
    instrument "$SOURCE_FILE" "$GLOBALS_FILE" "$HASHES_FILE"
} > "$INSTR_FILE"

if [ "$DRY_RUN" -eq 1 ]; then
    cat "$INSTR_FILE"
    exit 0
fi

# --- Compile and run ---
BIN_FILE="$TMP_DIR/race_bin"
if ! "$JDA" "$INSTR_FILE" "$BIN_FILE" >/dev/null 2>"$TMP_DIR/compile_err.txt"; then
    echo "jda-race: compilation failed" >&2
    cat "$TMP_DIR/compile_err.txt" >&2
    exit 1
fi
chmod +x "$BIN_FILE"
"$BIN_FILE"
