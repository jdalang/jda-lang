#!/bin/bash
set -euo pipefail

# jda-bench — Go-style benchmarking for Jda
#
# Discovers fn bench_*(n: i64) functions in .jda files, generates a main()
# wrapper that calls the function with N iterations, compiles, and times
# execution. Auto-calibrates N to reach target duration.
#
# Benchmark function signature:
#   fn bench_fib(n: i64) {
#       let i = 0
#       loop i < n { fib(25); i = i + 1 }
#   }
#
# Usage:
#   jda bench <file.jda>                        Benchmark all bench_* functions
#   jda bench --count 1000 <file.jda>           Fixed iteration count
#   jda bench --time 3 <file.jda>               Target seconds (default: 1)
#   jda bench --json <file.jda>                 Output JSON results
#   jda bench --compare baseline.json <file.jda> Compare against baseline

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
JDA="${JDA:-$PROJECT_ROOT/bootstrap/stage0/jda1}"

OPT_COUNT=0
OPT_TIME=1
OPT_JSON=0
OPT_COMPARE=""
FILES=()

usage() {
    cat << 'EOF'
jda-bench — Go-style benchmarking for Jda

Discovers fn bench_*(n: i64) functions, auto-calibrates iteration count,
and reports ns/op.

Output format (Go-style):
  bench_fib       1000        1234567 ns/op
  bench_sum     500000            234 ns/op

Usage:
  jda bench <file.jda>                        Benchmark all bench_* functions
  jda bench --count 1000 <file.jda>           Fixed iteration count
  jda bench --time 3 <file.jda>               Target seconds (default: 1)
  jda bench --json <file.jda>                 Output JSON results
  jda bench --compare baseline.json <file.jda> Compare against baseline
EOF
}

while (( $# > 0 )); do
    case "$1" in
        --count|-n)  OPT_COUNT="$2"; shift 2 ;;
        --time|-t)   OPT_TIME="$2"; shift 2 ;;
        --json)      OPT_JSON=1; shift ;;
        --compare)   OPT_COMPARE="$2"; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        -*)          echo "jda-bench: unknown option '$1'" >&2; exit 1 ;;
        *)           FILES+=("$1"); shift ;;
    esac
done

if (( ${#FILES[@]} == 0 )); then
    echo "usage: jda bench [options] <file.jda>" >&2
    exit 1
fi

# ─── Discovery ───────────────────────────────────────────────────────────────

find_bench_targets() {
    awk '/^[[:space:]]*fn[[:space:]]+bench_[a-zA-Z0-9_]+[[:space:]]*\(/ {
        name = $0; sub(/.*fn[[:space:]]+/, "", name); sub(/[^a-zA-Z0-9_].*/, "", name)
        print name
    }' "$1"
}

# ─── Wrapper: compile bench_X(N) with N baked into the binary ────────────────

compile_for_n() {
    local source_file="$1" target_name="$2" n="$3" bin_out="$4"
    local wrapper="${bin_out}.jda"

    cat "$source_file" > "$wrapper"
    cat >> "$wrapper" << EOF

fn main() {
    ${target_name}(${n})
}
EOF
    "$JDA" "$wrapper" "$bin_out" >/dev/null 2>&1
    local rc=$?
    rm -f "$wrapper"
    if (( rc != 0 )); then return 1; fi
    chmod +x "$bin_out"
}

# ─── Timing: use bash date +%s%N ─────────────────────────────────────────────

time_ns() {
    date +%s%N
}

run_timed() {
    local binary="$1"
    local start end
    start=$(time_ns)
    "$binary" >/dev/null 2>&1 || true
    end=$(time_ns)
    echo $(( end - start ))
}

# ─── Auto-calibrate ─────────────────────────────────────────────────────────

calibrate() {
    local source_file="$1" target_name="$2" bin_out="$3"
    local target_ns=$(( OPT_TIME * 1000000000 ))
    local n=1
    local elapsed=0

    while true; do
        compile_for_n "$source_file" "$target_name" "$n" "$bin_out" || { echo "0 0"; return; }
        elapsed=$(run_timed "$bin_out")

        if (( elapsed >= 100000000 )); then  # >= 100ms
            break
        fi
        if (( n >= 1000000000 )); then
            break
        fi
        n=$(( n * 10 ))
    done

    # Extrapolate to target time
    if (( elapsed > 0 )); then
        local ns_per_op=$(( elapsed / n ))
        if (( ns_per_op > 0 )); then
            n=$(( target_ns / ns_per_op ))
            if (( n < 1 )); then n=1; fi
            if (( n > 1000000000 )); then n=1000000000; fi
        fi
    fi

    # Final run with calibrated N
    compile_for_n "$source_file" "$target_name" "$n" "$bin_out" || { echo "0 0"; return; }
    elapsed=$(run_timed "$bin_out")
    echo "$n $elapsed"
}

# ─── Formatting ──────────────────────────────────────────────────────────────

format_ns() {
    local ns="$1"
    if (( ns >= 1000000000 )); then
        awk "BEGIN{printf \"%.2f s\", $ns/1000000000}"
    elif (( ns >= 1000000 )); then
        awk "BEGIN{printf \"%.2f ms\", $ns/1000000}"
    elif (( ns >= 1000 )); then
        awk "BEGIN{printf \"%.2f us\", $ns/1000}"
    else
        echo "${ns} ns"
    fi
}

# ─── Main ────────────────────────────────────────────────────────────────────

TMP_DIR=$(mktemp -d /tmp/jda_bench_XXXXXX)
trap "rm -rf $TMP_DIR" EXIT

JSON_RESULTS="["
JSON_FIRST=1
TOTAL_BENCHMARKS=0
TOTAL_PASS=0

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
        targets=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && targets+=("$line")
        done < <(find_bench_targets "$jda_file")

        (( ${#targets[@]} == 0 )) && continue

        if (( OPT_JSON == 0 )); then
            echo ""
            echo "=== ${jda_file}: ${#targets[@]} benchmark(s) ==="
            echo ""
        fi

        for target_name in "${targets[@]}"; do
            TOTAL_BENCHMARKS=$(( TOTAL_BENCHMARKS + 1 ))
            bin_out="$TMP_DIR/${target_name}"

            local_n=0
            local_elapsed=0
            local_ns_per_op=0

            if (( OPT_COUNT > 0 )); then
                if ! compile_for_n "$jda_file" "$target_name" "$OPT_COUNT" "$bin_out"; then
                    (( OPT_JSON == 0 )) && printf "%-30s  FAIL (compile error)\n" "$target_name"
                    continue
                fi
                local_n=$OPT_COUNT
                local_elapsed=$(run_timed "$bin_out")
            else
                read local_n local_elapsed <<< "$(calibrate "$jda_file" "$target_name" "$bin_out")"
            fi

            if (( local_n == 0 || local_elapsed == 0 )); then
                (( OPT_JSON == 0 )) && printf "%-30s  FAIL\n" "$target_name"
                continue
            fi

            local_ns_per_op=$(( local_elapsed / local_n ))
            TOTAL_PASS=$(( TOTAL_PASS + 1 ))

            if (( OPT_JSON == 0 )); then
                printf "%-30s  %10d  %14d ns/op    (%s)\n" \
                    "$target_name" "$local_n" "$local_ns_per_op" "$(format_ns "$local_elapsed")"
            fi

            (( JSON_FIRST == 0 )) && JSON_RESULTS="${JSON_RESULTS},"
            JSON_FIRST=0
            JSON_RESULTS="${JSON_RESULTS}{\"name\":\"${target_name}\",\"n\":${local_n},\"ns_per_op\":${local_ns_per_op},\"total_ns\":${local_elapsed}}"
        done
    done
done

JSON_RESULTS="${JSON_RESULTS}]"
(( OPT_JSON == 1 )) && echo "$JSON_RESULTS"

# ─── Baseline Comparison ────────────────────────────────────────────────────

if [[ -n "$OPT_COMPARE" ]] && [[ -f "$OPT_COMPARE" ]]; then
    echo ""
    echo "=== Regression Check (vs $(basename "$OPT_COMPARE")) ==="

    REGRESSED=0

    for entry in $(echo "$JSON_RESULTS" | grep -o '"name":"[^"]*","n":[0-9]*,"ns_per_op":[0-9]*' | sed 's/"name":"//;s/","n":/|/;s/,"ns_per_op":/|/'); do
        IFS='|' read -r bname bn bns <<< "$entry"
        baseline_ns=$(grep -o "\"name\":\"${bname}\"[^}]*\"ns_per_op\":[0-9]*" "$OPT_COMPARE" 2>/dev/null | grep -o '"ns_per_op":[0-9]*' | grep -o '[0-9]*' || echo "")

        if [[ -z "$baseline_ns" ]] || [[ "$baseline_ns" == "0" ]]; then
            printf "  %-30s  NEW (%d ns/op)\n" "$bname" "$bns"
            continue
        fi

        diff=$(( bns - baseline_ns ))
        (( baseline_ns > 0 )) && pct=$(( diff * 100 / baseline_ns )) || pct=0

        if (( pct > 5 )); then
            printf "  %-30s  REGRESSION +%d%% (%d -> %d ns/op)\n" "$bname" "$pct" "$baseline_ns" "$bns"
            REGRESSED=1
        elif (( pct < -5 )); then
            printf "  %-30s  IMPROVED %d%% (%d -> %d ns/op)\n" "$bname" "$pct" "$baseline_ns" "$bns"
        else
            printf "  %-30s  OK %d%% (%d -> %d ns/op)\n" "$bname" "$pct" "$baseline_ns" "$bns"
        fi
    done

    (( REGRESSED == 1 )) && echo "" && echo "WARNING: Performance regression detected (>5%)"
fi

# ─── Summary ────────────────────────────────────────────────────────────────

if (( OPT_JSON == 0 )); then
    echo ""
    echo "=== Benchmark Summary ==="
    echo "  Benchmarks: ${TOTAL_BENCHMARKS}"
    echo "  Passed:     ${TOTAL_PASS}"
fi
