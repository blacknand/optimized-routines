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
    cache-misses:u cache-references:u alignment-faults:u
    bus-cycles:u branches:u branch-misses:u
)
event_batch_sizes=(2 3 2)

for workload in random deterministic; do
    printf '\nmemset_%s\n' "$workload"
    for ((event_index = 0, batch_index = 0; event_index < ${#events[@]}; event_index += batch_size, batch_index++)); do
        batch_size="${event_batch_sizes[batch_index % ${#event_batch_sizes[@]}]}"
        event_batch="${events[event_index]}"
        for ((batch_offset = 1; batch_offset < batch_size && event_index + batch_offset < ${#events[@]}; batch_offset++)); do
            event_batch+=",${events[event_index + batch_offset]}"
        done
        printf '\nEvents: %s\n' "$event_batch"
        perf stat -B -r 5 -e "$event_batch" -- ./memset-driver "--$workload" || exit "$?"
    done
done

perf record -e cycles:u,instructions:u,branches:u -F 999 -- ./memset-driver
perf report
perf annotate -d ./memset-driver
