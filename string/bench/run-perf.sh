#!/bin/bash

aor_root="$(pwd -P)" || exit 1
git_root="$(git -C "$aor_root" rev-parse --show-toplevel 2>/dev/null)" || git_root=

if [[ "$aor_root" != "$git_root" ||
      ! -f "$aor_root/Makefile" ||
      ! -f "$aor_root/string/Dir.mk" ||
      ! -f "$aor_root/string/aarch64/memset-sve.S" ||
      ! -f "$aor_root/string/bench/memset-driver.c" ]]; then
    printf 'Error: run-perf.sh must be run from the root of an AoR worktree (got %s).\n' \
        "$aor_root" >&2
    exit 1
fi

bench_cpu="${BENCH_CPU:-3}"
printf 'AoR worktree: %s (CPU %s)\n' "$aor_root" "$bench_cpu"

compile=false
record=false

while (( $# > 0)); do
    case "$1" in
        --compile)
            compile=true
	    shift
            ;;
        --record)
            record=true
	    shift
            ;;
        *)
            break
            ;;
    esac
done

if [[ "$compile" == true ]]; then
    gcc string/bench/memset-driver.c string/aarch64/memset-sve.S \
        -O0 -o memset-driver \
        -I string/include \
        -ggdb # Required for perf annotate
    compile_status=$?
    if [[ "$compile_status" -ne 0 ]]; then
        printf 'Could not compile memset driver, exiting script now'
        exit "$compile_status"
    fi
    printf 'Successfully compiled the memset driver\n'
fi

events=(
    cycles:u instructions:u
    cache-misses:u cache-references:u
    branches:u branch-misses:u
    alignment-faults:u page-faults:u
    bus-cycles:u
)

if [[ "$record" == true ]]; then
    taskset -c "$bench_cpu" perf record --no-buildid-cache \
        -o memset-random.perf.data \
        -e '{cycles:u,branch-misses:u}' -F 999 \
        -- ./memset-driver --random || exit "$?"

    perf report --stdio --no-children --show-nr-samples \
        --symbols=__memset_aarch64_sve --percentage absolute \
        -i memset-random.perf.data || exit "$?"

    perf annotate --stdio --verbose \
        -s __memset_aarch64_sve --percent-type=local-period \
        -i memset-random.perf.data || exit "$?"
fi

results_dir="$aor_root/string/bench/perf-results"
mkdir -p "$results_dir" || exit "$?"
results_file="$results_dir/result-$(date -u +%M-%H-%d-%m-%Y)"
touch "$results_file" || exit "$?"

printf 'Running perf stat, check %s\n' "$results_file"

# Codex generated
perf_pid=
stop_perf() {
    local exit_status="$1"
    trap '' INT TERM
    if [[ -n "$perf_pid" ]]; then
        kill -TERM -- "-$perf_pid" 2>/dev/null || true
        wait "$perf_pid" 2>/dev/null || true
    fi
    printf '\nStopped. Results saved in %s\n' "$results_file" >&2
    exit "$exit_status"
}
trap 'stop_perf 130' INT
trap 'stop_perf 143' TERM

for workload in random deterministic; do
    for ((event_index = 0; event_index < ${#events[@]}; event_index += 2)); do
        if (( event_index == ${#events[@]} - 1 )); then
            event_batch="${events[event_index]}"
        else
            event_batch="{${events[event_index]},${events[event_index + 1]}}"
        fi
        setsid taskset -c "$bench_cpu" perf stat -B -r 5 -e "$event_batch" \
            --append --output "$results_file" -- ./memset-driver "--$workload" &
        perf_pid=$!
        wait "$perf_pid" || exit "$?"
        perf_pid=
    done
done
