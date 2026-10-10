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
        exit "$compile_status"
    fi
fi

events=(
    cycles:u instructions:u
    cache-misses:u cache-references:u
    branches:u branch-misses:u
    alignment-faults:u bus-cycles:u
)

if [[ "$record" == true ]]; then
    taskset -c 3 perf record --no-buildid-cache \
        -o memset-random.perf.data \
        -e cycles:u -F 999 \
        -- ./memset-driver --random || exit "$?"

    perf report --stdio --no-children --show-nr-samples \
        --symbols=__memset_aarch64_sve --percentage absolute \
        -i memset-random.perf.data || exit "$?"

    perf annotate --stdio --show-nr-samples \
        -s __memset_aarch64_sve \
        -i memset-random.perf.data || exit "$?"
fi

for workload in random deterministic; do
    printf '\nmemset_%s\n' "$workload"
    for ((event_index = 0; event_index < ${#events[@]}; event_index += 2)); do
	event_batch="{${events[event_index]},${events[event_index + 1]}}"
        taskset -c 3 perf stat -B -r 5 -e "$event_batch" -- ./memset-driver "--$workload" || exit "$?"
    done
done