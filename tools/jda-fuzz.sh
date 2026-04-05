#!/bin/bash
set -euo pipefail

# jda-fuzz — Built-in fuzz testing for Jda
#
# Discovers fn fuzz_* functions in .jda files, generates random inputs,
# compiles once, and runs repeatedly to find crashes.
#
# Fuzz target signature:
#   fn fuzz_example(a: i64, b: i64) {
#       ; test code here — crash (exit non-zero) means bug found
#   }
#
# Usage:
#   jda-fuzz.sh <file.jda>                    Fuzz all fuzz_* functions
#   jda-fuzz.sh --runs 10000 <file.jda>       Set iteration count (default: 1000)
#   jda-fuzz.sh --time 30 <file.jda>          Run for N seconds
#   jda-fuzz.sh --seed 42 <file.jda>          Reproducible random seed
#   jda-fuzz.sh --corpus <dir> <file.jda>     Save/load crash corpus
#
# Crash corpus files are saved as one-line-per-arg text files.
# Re-running with --corpus replays saved crashes as regression tests first.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
JDA="${JDA:-$PROJECT_ROOT/bootstrap/stage0/jda1}"

# Interesting i64 values for mutations
INTERESTING_VALUES=(
    0 1 -1 2 -2
    127 128 -128 -129
    255 256 -256
    32767 32768 -32768 -32769
    65535 65536
    2147483647 2147483648 -2147483648 -2147483649
    9223372036854775807 -9223372036854775808
    6148914691236517205 -6148914691236517206
    3735928559 3405691582
)

# --- Random number generation ---

# Seed the bash RANDOM (limited to 32767, so we also use /dev/urandom for big values)
fuzz_seed=0

rand_init() {
    fuzz_seed="$1"
    RANDOM="$fuzz_seed"
}

# Generate a random i64 value (full 64-bit range, signed)
rand_i64() {
    # Read 8 bytes from urandom, interpret as unsigned, then treat as signed
    local hex
    hex=$(od -A n -t x1 -N 8 /dev/urandom | tr -d ' \n')
    # Convert hex to decimal using python-free approach: printf + bc or shell arithmetic
    # Shell arithmetic is limited to 63-bit signed, so we use two 32-bit halves
    local hi lo val
    hi=$((16#${hex:0:8}))
    lo=$((16#${hex:8:8}))
    val=$(( (hi << 32) | lo ))
    echo "$val"
}

# Generate a random integer in range [lo, hi] inclusive
rand_range() {
    local lo="$1" hi="$2"
    local span=$(( hi - lo + 1 ))
    local r=$(( RANDOM % span ))
    echo $(( lo + r ))
}

# Pick a random element from INTERESTING_VALUES
rand_interesting() {
    local idx=$(( RANDOM % ${#INTERESTING_VALUES[@]} ))
    echo "${INTERESTING_VALUES[$idx]}"
}

# --- Fuzz target discovery ---

# Find fuzz_* functions: outputs "name param_count" per line
find_fuzz_targets() {
    local file="$1"
    awk '/^[[:space:]]*fn[[:space:]]+fuzz_[a-zA-Z0-9_]+[[:space:]]*\(/ {
        # Extract function name
        name = $0; sub(/.*fn[[:space:]]+/, "", name); sub(/[^a-zA-Z0-9_].*/, "", name)
        # Extract parameter list between parens
        params = $0; sub(/^[^(]*\(/, "", params); sub(/\).*/, "", params)
        # Remove whitespace
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", params)
        if (params == "") {
            print name, 0
        } else {
            # Count commas + 1
            n = gsub(/,/, ",", params) + 1
            print name, n
        }
    }' "$file"
}

# --- Wrapper generation ---

generate_wrapper() {
    local source_file="$1"
    local target_name="$2"
    local param_count="$3"
    local output_file="$4"

    # Copy source
    cat "$source_file" > "$output_file"

    # Append helper functions and main
    cat >> "$output_file" << 'WRAPPER_HELPERS'

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
WRAPPER_HELPERS

    # Generate argument parsing lines
    local i
    for (( i = 0; i < param_count; i++ )); do
        echo "    let arg${i} = fuzz_parse_i64(buf, pos[0], pos)" >> "$output_file"
    done

    # Generate call
    local args=""
    for (( i = 0; i < param_count; i++ )); do
        if (( i > 0 )); then
            args="${args}, "
        fi
        args="${args}arg${i}"
    done
    echo "    ${target_name}(${args})" >> "$output_file"
    echo "}" >> "$output_file"
}

# --- Input generation ---

generate_input() {
    local param_count="$1"
    local strategy=$(( RANDOM % 5 ))
    local values=()
    local i

    for (( i = 0; i < param_count; i++ )); do
        local val
        case "$strategy" in
            0) # Pure random i64
                val=$(rand_i64)
                ;;
            1) # Interesting values
                val=$(rand_interesting)
                ;;
            2) # Small values [-100, 100]
                val=$(rand_range -100 100)
                ;;
            3) # Powers of two +/- 1
                local exp=$(( RANDOM % 63 ))
                local base=$(( 1 << exp ))
                local delta_choices=(-1 0 1)
                local delta=${delta_choices[$(( RANDOM % 3 ))]}
                val=$(( base + delta ))
                ;;
            4) # Bit pattern mutations (random i64)
                val=$(rand_i64)
                ;;
        esac
        values+=("$val")
    done

    # Output space-separated
    echo "${values[*]}"
}

# --- Corpus management ---

load_corpus() {
    local corpus_dir="$1"
    local target_name="$2"
    local target_dir="${corpus_dir}/${target_name}"

    if [[ ! -d "$target_dir" ]]; then
        return
    fi

    local f
    for f in "$target_dir"/crash_*; do
        [[ -f "$f" ]] || continue
        # Read lines as space-separated values
        local vals
        vals=$(tr '\n' ' ' < "$f" | sed 's/[[:space:]]*$//')
        if [[ -n "$vals" ]]; then
            echo "$vals"
        fi
    done
}

save_crash() {
    local corpus_dir="$1"
    local target_name="$2"
    local values="$3"
    local crash_num="$4"

    local target_dir="${corpus_dir}/${target_name}"
    mkdir -p "$target_dir"

    local fname
    fname=$(printf "%s/crash_%04d" "$target_dir" "$crash_num")

    # Write one value per line
    echo "$values" | tr ' ' '\n' > "$fname"
    echo "$fname"
}

# --- Run one test ---

run_one() {
    local binary="$1"
    local values="$2"
    local stdin_data="${values}
"
    local exit_code=0
    echo -n "$stdin_data" | timeout 5 "$binary" > /dev/null 2>"$FUZZ_STDERR_FILE" || exit_code=$?
    echo "$exit_code"
}

# --- Fuzz a single target ---

fuzz_target() {
    local source_file="$1"
    local target_name="$2"
    local param_count="$3"
    local max_runs="$4"
    local max_time="$5"
    local seed="$6"
    local corpus_dir="$7"

    rand_init "$seed"

    # Generate wrapper source
    local src_path
    src_path=$(mktemp /tmp/jda_fuzz_XXXXXX.jda)
    local bin_path="${src_path%.jda}"

    generate_wrapper "$source_file" "$target_name" "$param_count" "$src_path"

    # Compile
    local compile_exit=0
    "$JDA" "$src_path" "$bin_path" > /dev/null 2>&1 || compile_exit=$?
    if (( compile_exit != 0 )); then
        echo "  FAIL  ${target_name}: compile error"
        rm -f "$src_path"
        echo "0 0 0"
        return
    fi
    chmod +x "$bin_path"

    local crashes=0
    local total_runs=0
    local start_time
    start_time=$(date +%s)

    # Phase 1: Replay corpus
    if [[ -n "$corpus_dir" ]]; then
        local corpus_inputs
        corpus_inputs=$(load_corpus "$corpus_dir" "$target_name")
        if [[ -n "$corpus_inputs" ]]; then
            local count
            count=$(echo "$corpus_inputs" | wc -l | tr -d ' ')
            echo "  ${target_name}: replaying ${count} corpus entries..."
            while IFS= read -r values; do
                local code
                code=$(run_one "$bin_path" "$values")
                total_runs=$(( total_runs + 1 ))
                if (( code != 0 )); then
                    crashes=$(( crashes + 1 ))
                    echo "  CRASH (corpus replay) ${target_name}(${values// /, }) exit=${code}"
                fi
            done <<< "$corpus_inputs"
        fi
    fi

    # Phase 2: Random fuzzing
    echo "  ${target_name}: fuzzing with seed=${seed}, params=${param_count}..."

    local run_count=0
    local last_report
    last_report=$(date +%s)

    while true; do
        # Check termination
        if (( max_time > 0 )); then
            local now
            now=$(date +%s)
            if (( now - start_time >= max_time )); then
                break
            fi
        else
            if (( run_count >= max_runs )); then
                break
            fi
        fi

        local values
        values=$(generate_input "$param_count")
        local code
        code=$(run_one "$bin_path" "$values")
        run_count=$(( run_count + 1 ))
        total_runs=$(( total_runs + 1 ))

        if (( code != 0 )); then
            crashes=$(( crashes + 1 ))
            echo "  CRASH #${crashes} ${target_name}(${values// /, }) exit=${code}"
            if [[ -n "$corpus_dir" ]]; then
                local fname
                fname=$(save_crash "$corpus_dir" "$target_name" "$values" "$crashes")
                echo "         saved to ${fname}"
            fi
        fi

        # Progress report every 5 seconds
        local now
        now=$(date +%s)
        if (( now - last_report >= 5 )); then
            local elapsed=$(( now - start_time ))
            local rate=0
            if (( elapsed > 0 )); then
                rate=$(( total_runs / elapsed ))
            fi
            echo "  ${target_name}: ${total_runs} runs, ${crashes} crashes, ${rate} runs/sec"
            last_report=$now
        fi
    done

    # Cleanup
    rm -f "$src_path" "$bin_path"

    local end_time
    end_time=$(date +%s)
    local elapsed=$(( end_time - start_time ))
    local rate=0
    if (( elapsed > 0 )); then
        rate=$(( total_runs / elapsed ))
    fi
    echo "  ${target_name}: ${total_runs} runs in ${elapsed}s (${rate}/sec), ${crashes} crashes"

    # Return results via global variables
    _FUZZ_RUNS=$total_runs
    _FUZZ_CRASHES=$crashes
}

# --- Main ---

usage() {
    cat << 'EOF'
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

Crash corpus files are saved as one-line-per-arg text files.
Re-running with --corpus replays saved crashes as regression tests first.
EOF
}

# Parse arguments
OPT_RUNS=1000
OPT_TIME=0
OPT_SEED=""
OPT_CORPUS=""
FILES=()

while (( $# > 0 )); do
    case "$1" in
        --runs)
            OPT_RUNS="$2"; shift 2 ;;
        --time)
            OPT_TIME="$2"; shift 2 ;;
        --seed)
            OPT_SEED="$2"; shift 2 ;;
        --corpus)
            OPT_CORPUS="$2"; shift 2 ;;
        --workers)
            shift 2 ;;  # accepted but ignored in bash version
        -h|--help)
            usage; exit 0 ;;
        -*)
            echo "jda-fuzz: unknown option '$1'" >&2; exit 1 ;;
        *)
            FILES+=("$1"); shift ;;
    esac
done

if (( ${#FILES[@]} == 0 )); then
    echo "usage: jda-fuzz.sh [options] <file.jda>" >&2
    exit 1
fi

# Default seed from epoch seconds
if [[ -z "$OPT_SEED" ]]; then
    OPT_SEED=$(date +%s)
fi

# Temp file for stderr capture
FUZZ_STDERR_FILE=$(mktemp /tmp/jda_fuzz_stderr_XXXXXX)
trap 'rm -f "$FUZZ_STDERR_FILE"' EXIT

TOTAL_RUNS=0
TOTAL_CRASHES=0
TOTAL_TARGETS=0

# Global return values from fuzz_target
_FUZZ_RUNS=0
_FUZZ_CRASHES=0

for filepath in "${FILES[@]}"; do
    jda_files=()
    if [[ -d "$filepath" ]]; then
        while IFS= read -r f; do
            jda_files+=("$f")
        done < <(find "$filepath" -maxdepth 1 -name '*.jda' -type f | sort)
    else
        jda_files=("$filepath")
    fi

    for jda_file in "${jda_files[@]}"; do
        # Find targets
        targets=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && targets+=("$line")
        done < <(find_fuzz_targets "$jda_file")

        if (( ${#targets[@]} == 0 )); then
            continue
        fi

        echo ""
        echo "=== ${jda_file}: ${#targets[@]} fuzz target(s) ==="

        for entry in "${targets[@]}"; do
            local_name="${entry%% *}"
            local_count="${entry##* }"

            if (( local_count == 0 )); then
                echo "  SKIP  ${local_name}: no parameters to fuzz"
                continue
            fi

            TOTAL_TARGETS=$(( TOTAL_TARGETS + 1 ))

            fuzz_target "$jda_file" "$local_name" "$local_count" \
                "$OPT_RUNS" "$OPT_TIME" "$OPT_SEED" "$OPT_CORPUS"

            TOTAL_RUNS=$(( TOTAL_RUNS + _FUZZ_RUNS ))
            TOTAL_CRASHES=$(( TOTAL_CRASHES + _FUZZ_CRASHES ))
        done
    done
done

echo ""
echo "=== Fuzz Summary ==="
echo "  Targets: ${TOTAL_TARGETS}"
echo "  Runs:    ${TOTAL_RUNS}"
echo "  Crashes: ${TOTAL_CRASHES}"

if (( TOTAL_CRASHES > 0 )); then
    exit 1
fi
exit 0
