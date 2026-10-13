#!/bin/bash

cd /work/gnu/src/optimized-routines

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
    taskset -c 3 perf record --no-buildid-cache \
        -o memset-random.perf.data \
        -e cycles:u -F 999 \
        -- ./memset-driver --random || exit "$?"

    perf report --stdio --no-children --show-nr-samples \
        --symbols=__memset_aarch64_sve --percentage absolute \
        -i memset-random.perf.data || exit "$?"

    perf annotate --stdio --verbose \
        -s __memset_aarch64_sve --percent-type=local-period \
        -i memset-random.perf.data || exit "$?"
fi

results_dir=/work/gnu/src/optimized-routines/string/bench/perf-results
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
        setsid taskset -c 3 perf stat -B -r 5 -e "$event_batch" \
            --append --output "$results_file" -- ./memset-driver "--$workload" &
        perf_pid=$!
        wait "$perf_pid" || exit "$?"
        perf_pid=
    done
done
