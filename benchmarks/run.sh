#!/bin/bash
# Jda Benchmark Suite — measures execution time, compilation time, binary size
# Run inside Docker: docker build -t jda-bench benchmarks/ && docker run --rm -v $(PWD):/jda jda-bench bash /jda/benchmarks/run.sh
set -e

BENCHMARKS="fib35 sieve sum_loop matmul json_parse"
LANGS="c go rust jda python ruby"
RUNS=3  # number of runs per benchmark, take best time
RESULTS_FILE="/jda/benchmarks/results.csv"
OUTDIR="/tmp/bench_bin"
mkdir -p "$OUTDIR"

echo "language,benchmark,compile_ms,run_ms,binary_bytes" > "$RESULTS_FILE"

time_ms() {
    # Returns wall-clock time in milliseconds
    local start end
    start=$(date +%s%N)
    "$@" > /dev/null 2>&1
    end=$(date +%s%N)
    echo $(( (end - start) / 1000000 ))
}

best_run_ms() {
    local cmd="$1"
    local best=999999999
    for i in $(seq 1 $RUNS); do
        local start end elapsed
        start=$(date +%s%N)
        eval "$cmd" > /dev/null 2>&1
        end=$(date +%s%N)
        elapsed=$(( (end - start) / 1000000 ))
        if [ "$elapsed" -lt "$best" ]; then
            best=$elapsed
        fi
    done
    echo "$best"
}

for bench in $BENCHMARKS; do
    echo "=== Benchmark: $bench ==="

    # --- C ---
    echo "  [C] compiling..."
    compile_ms=$(time_ms gcc -O2 -o "$OUTDIR/c_$bench" "/jda/benchmarks/c/$bench.c")
    bin_size=$(stat -c%s "$OUTDIR/c_$bench" 2>/dev/null || echo 0)
    echo "  [C] running ($RUNS runs)..."
    run_ms=$(best_run_ms "$OUTDIR/c_$bench")
    echo "c,$bench,$compile_ms,$run_ms,$bin_size" >> "$RESULTS_FILE"
    echo "  [C] compile=${compile_ms}ms run=${run_ms}ms size=${bin_size}B"

    # --- Go ---
    echo "  [Go] compiling..."
    compile_ms=$(time_ms go build -o "$OUTDIR/go_$bench" "/jda/benchmarks/go/$bench.go")
    bin_size=$(stat -c%s "$OUTDIR/go_$bench" 2>/dev/null || echo 0)
    echo "  [Go] running ($RUNS runs)..."
    run_ms=$(best_run_ms "$OUTDIR/go_$bench")
    echo "go,$bench,$compile_ms,$run_ms,$bin_size" >> "$RESULTS_FILE"
    echo "  [Go] compile=${compile_ms}ms run=${run_ms}ms size=${bin_size}B"

    # --- Rust ---
    echo "  [Rust] compiling..."
    compile_ms=$(time_ms rustc -O -o "$OUTDIR/rust_$bench" "/jda/benchmarks/rust/$bench.rs")
    bin_size=$(stat -c%s "$OUTDIR/rust_$bench" 2>/dev/null || echo 0)
    echo "  [Rust] running ($RUNS runs)..."
    run_ms=$(best_run_ms "$OUTDIR/rust_$bench")
    echo "rust,$bench,$compile_ms,$run_ms,$bin_size" >> "$RESULTS_FILE"
    echo "  [Rust] compile=${compile_ms}ms run=${run_ms}ms size=${bin_size}B"

    # --- Jda ---
    echo "  [Jda] compiling..."
    compile_ms=$(time_ms /jda/bootstrap/stage0/jda1 build "/jda/benchmarks/jda/$bench.jda" -o "$OUTDIR/jda_$bench")
    bin_size=$(stat -c%s "$OUTDIR/jda_$bench" 2>/dev/null || echo 0)
    echo "  [Jda] running ($RUNS runs)..."
    run_ms=$(best_run_ms "$OUTDIR/jda_$bench")
    echo "jda,$bench,$compile_ms,$run_ms,$bin_size" >> "$RESULTS_FILE"
    echo "  [Jda] compile=${compile_ms}ms run=${run_ms}ms size=${bin_size}B"

    # --- Python ---
    echo "  [Python] running ($RUNS runs)..."
    run_ms=$(best_run_ms "python3 /jda/benchmarks/python/$bench.py")
    echo "python,$bench,0,$run_ms,0" >> "$RESULTS_FILE"
    echo "  [Python] run=${run_ms}ms (interpreted)"

    # --- Ruby ---
    echo "  [Ruby] running ($RUNS runs)..."
    run_ms=$(best_run_ms "ruby /jda/benchmarks/ruby/$bench.rb")
    echo "ruby,$bench,0,$run_ms,0" >> "$RESULTS_FILE"
    echo "  [Ruby] run=${run_ms}ms (interpreted)"

    echo ""
done

# === HTTP Echo Server Benchmark ===
echo "=== Benchmark: http_echo ==="

if command -v wrk &> /dev/null && [ "${SKIP_HTTP:-0}" = "0" ]; then
    HTTP_DURATION="5s"
    HTTP_THREADS=2
    HTTP_CONNS=100

    run_http_bench() {
        local lang="$1"
        local cmd="$2"
        local is_compiled="$3"

        echo "  [$lang] starting server..."
        eval "$cmd" &
        local pid=$!
        sleep 1  # let server bind

        echo "  [$lang] running wrk (${HTTP_THREADS}t, ${HTTP_CONNS}c, ${HTTP_DURATION})..."
        local wrk_out
        wrk_out=$(wrk -t${HTTP_THREADS} -c${HTTP_CONNS} -d${HTTP_DURATION} http://localhost:8080/ 2>&1)
        local rps
        rps=$(echo "$wrk_out" | grep "Requests/sec" | awk '{print $2}' | cut -d. -f1)
        local lat
        lat=$(echo "$wrk_out" | grep "Latency" | awk '{print $2}')

        kill $pid 2>/dev/null; wait $pid 2>/dev/null
        echo "  [$lang] req/sec=${rps} latency=${lat}"
        echo "$lang,http_echo,0,$rps,0" >> "$RESULTS_FILE"
    }

    # C
    gcc -O2 -o "$OUTDIR/c_http_echo" /jda/benchmarks/c/http_echo.c
    run_http_bench "C" "$OUTDIR/c_http_echo" 1

    # Go
    go build -o "$OUTDIR/go_http_echo" /jda/benchmarks/go/http_echo.go
    run_http_bench "Go" "$OUTDIR/go_http_echo" 1

    # Rust
    rustc -O -o "$OUTDIR/rust_http_echo" /jda/benchmarks/rust/http_echo.rs
    run_http_bench "Rust" "$OUTDIR/rust_http_echo" 1

    # Jda
    /jda/bootstrap/stage0/jda1 build /jda/benchmarks/jda/http_echo.jda -o "$OUTDIR/jda_http_echo"
    run_http_bench "Jda" "$OUTDIR/jda_http_echo" 1

    # Python
    run_http_bench "Python" "python3 /jda/benchmarks/python/http_echo.py" 0

    # Ruby
    run_http_bench "Ruby" "ruby /jda/benchmarks/ruby/http_echo.rb" 0

    echo ""
else
    echo "  [SKIP] wrk not installed — skipping HTTP benchmark"
    echo "  Install wrk: apt-get install wrk"
    echo ""
fi

echo "=== Results saved to $RESULTS_FILE ==="
echo ""
cat "$RESULTS_FILE" | column -t -s, 2>/dev/null || cat "$RESULTS_FILE"
