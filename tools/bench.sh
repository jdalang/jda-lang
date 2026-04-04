#!/bin/bash
# Jda Benchmark Suite
# Compiles and runs benchmarks in Jda and C, compares execution times.
# Must be run inside Docker: docker run --rm --platform linux/amd64 \
#   --ulimit stack=524288000:524288000 -v $(PWD):/jda -w /jda jda-build bash tools/bench.sh
#
# Install gcc first if not present:
#   apt-get update -qq && apt-get install -y -qq gcc >/dev/null 2>&1

set -e

JDA1="bootstrap/stage0/jda1"
BENCH_DIR="benchmarks"
TMP="/tmp/bench"
mkdir -p "$TMP"

BENCHMARKS="fib35 sieve sum_loop"

HAS_GCC=0
if command -v gcc >/dev/null 2>&1; then
    HAS_GCC=1
fi

# Install gcc if not present
if [ "$HAS_GCC" -eq 0 ]; then
    printf "Installing gcc..."
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq gcc >/dev/null 2>&1
    if command -v gcc >/dev/null 2>&1; then
        HAS_GCC=1
        printf " done.\n"
    else
        printf " failed. Skipping C comparison.\n"
    fi
fi

printf "\n=== Jda Benchmark Suite ===\n\n"

if [ "$HAS_GCC" -eq 1 ]; then
    printf "%-14s  %10s  %10s  %8s  %s\n" "Benchmark" "C -O2 (s)" "Jda (s)" "Ratio" "Status"
    printf "%-14s  %10s  %10s  %8s  %s\n" "---------" "---------" "-------" "-----" "------"
else
    printf "%-14s  %10s  %s\n" "Benchmark" "Jda (s)" "Status"
    printf "%-14s  %10s  %s\n" "---------" "-------" "------"
fi

total_pass=0
total_fail=0

for bench in $BENCHMARKS; do
    jda_src="$BENCH_DIR/jda/${bench}.jda"
    c_src="$BENCH_DIR/c/${bench}.c"

    # Compile Jda version
    "$JDA1" "$jda_src" "$TMP/${bench}_jda" 2>/dev/null
    chmod +x "$TMP/${bench}_jda"

    # Run Jda and capture output + time
    jda_start=$(date +%s%N)
    jda_out=$("$TMP/${bench}_jda" 2>/dev/null)
    jda_end=$(date +%s%N)
    jda_ms=$(( (jda_end - jda_start) / 1000000 ))
    jda_sec=$(awk "BEGIN{printf \"%.3f\", $jda_ms/1000}")

    if [ "$HAS_GCC" -eq 1 ]; then
        # Compile C version
        gcc -O2 -o "$TMP/${bench}_c" "$c_src" 2>/dev/null

        # Run C and capture output + time
        c_start=$(date +%s%N)
        c_out=$("$TMP/${bench}_c" 2>/dev/null)
        c_end=$(date +%s%N)
        c_ms=$(( (c_end - c_start) / 1000000 ))
        c_sec=$(awk "BEGIN{printf \"%.3f\", $c_ms/1000}")

        # Check correctness
        status="PASS"
        if [ "$c_out" != "$jda_out" ]; then
            status="FAIL (c=$c_out jda=$jda_out)"
            total_fail=$((total_fail + 1))
        else
            total_pass=$((total_pass + 1))
        fi

        # Calculate ratio
        if [ "$c_ms" -gt 0 ]; then
            ratio=$(awk "BEGIN{printf \"%.1fx\", $jda_ms/$c_ms}")
        else
            ratio="N/A"
        fi

        printf "%-14s  %10s  %10s  %8s  %s\n" "$bench" "$c_sec" "$jda_sec" "$ratio" "$status"
    else
        total_pass=$((total_pass + 1))
        printf "%-14s  %10s  %s\n" "$bench" "$jda_sec" "OK (output: $jda_out)"
    fi
done

# Self-compile benchmark
printf "\n=== Self-Compile Benchmark ===\n"
sc_start=$(date +%s%N)
"$JDA1" bootstrap/stage1/jda1.jda "$TMP/jda1_bench" 2>/dev/null
sc_end=$(date +%s%N)
sc_ms=$(( (sc_end - sc_start) / 1000000 ))
sc_sec=$(awk "BEGIN{printf \"%.3f\", $sc_ms/1000}")
printf "Self-compile jda1.jda:  %s seconds\n" "$sc_sec"

printf "\n=== Summary ===\n"
printf "  PASS: %d\n" "$total_pass"
printf "  FAIL: %d\n" "$total_fail"
printf "  Self-compile: %s s\n" "$sc_sec"

# Clean up
rm -rf "$TMP"
