#!/usr/bin/env bash

# If any command fails abort the entire script
set -euo pipefail
# If no Makefile exists in the glibc build, configure glibc again
mkdir -p /work/gnu/src/glibc-build
if [[ ! -f /work/gnu/src/glibc-build/Makefile ]]; then
  (
    cd /work/gnu/src/glibc-build
    ../glibc/configure --prefix=/opt/glibc-test
  )
fi

# Note that this is a new memset implementation, it does not replace the existing memset implementations (sve, generic SIMD, zva, etc.)
sve_source=/work/gnu/src/optimized-routines/string/aarch64/experimental/__memset_aarch64_sve2.S
sve_glibc=/work/gnu/src/glibc/sysdeps/aarch64/multiarch/__memset_aarch64_sve2.S

# Only update the glibc copy when its transformed contents have changed.  This
# avoids forcing an otherwise unnecessary glibc rebuild on every script run.
if ! cmp -s \
  <(sed 's|^#include "asmdefs.h"$|#include <sysdep.h>|' "$sve_source") \
  "$sve_glibc"; then
  sed 's|^#include "asmdefs.h"$|#include <sysdep.h>|' \
    "$sve_source" > "$sve_glibc"
fi

# Register the implementation with the build
if ! grep -Fq '__memset_aarch64_sve2' /work/gnu/src/glibc/sysdeps/aarch64/multiarch/Makefile; then
  # Insert the text before the memset_sve_zva64 line
  sed -i '/^[[:space:]]*memset_sve_zva64 \\/i\  __memset_aarch64_sve2 \\' /work/gnu/src/glibc/sysdeps/aarch64/multiarch/Makefile
fi

# Test and benchmark registration
if ! grep -Fq '__memset_aarch64_sve2' /work/gnu/src/glibc/sysdeps/aarch64/multiarch/ifunc-impl-list.c; then
  # Insert the text before the __memset_sve_zva64 line
  sed -i '/__memset_sve_zva64)/i\              IFUNC_IMPL_ADD (array, i, memset, sve2, __memset_aarch64_sve2)' /work/gnu/src/glibc/sysdeps/aarch64/multiarch/ifunc-impl-list.c
fi

# Skip irrelevant benchmarks: kunpeng and oryon
impl_list=/work/gnu/src/glibc/sysdeps/aarch64/multiarch/ifunc-impl-list.c

if grep -Fq \
  'IFUNC_IMPL_ADD (array, i, memset, (zva_size == 64), __memset_oryon1)' \
  "$impl_list"; then
  # Replace 4th argument with 0 to ensure the IFUNCs are never included
  sed -i \
    's|IFUNC_IMPL_ADD (array, i, memset, (zva_size == 64), __memset_oryon1)|IFUNC_IMPL_ADD (array, i, memset, 0, __memset_oryon1)|' \
    "$impl_list"
fi

if grep -Fq \
  'IFUNC_IMPL_ADD (array, i, memset, 1, __memset_kunpeng)' \
  "$impl_list"; then
  sed -i \
    's|IFUNC_IMPL_ADD (array, i, memset, 1, __memset_kunpeng)|IFUNC_IMPL_ADD (array, i, memset, 0, __memset_kunpeng)|' \
    "$impl_list"
fi

# NOTE: does make actually cache anything? Like with CMake, I am pretty sure if I build and then build again with no
# changes it should still be really quick because CMake caches everything. Else, do something to save time with building...

# TODO: List the top 5 worst cases and the parameters they use

run_tests=true
run_aor_benchmark=true
skip_glibc_build=false
skip_glibc_benchmark_build=false
skip_all_benchmarks=false
for arg in "$@"; do
  case $arg in
    --no-test) run_tests=false ;;
    --no-aor-bench) run_aor_benchmark=false ;;
    --skip-glibc-build) skip_glibc_build=true ;;
    --skip-glibc-benchmark-build) skip_glibc_benchmark_build=true ;;
    --skip-all-benchmarks) skip_all_benchmarks=true ;;
    *)
      printf 'usage: %s \n  [--no-test]\n' "$0" >&2
      printf '  [--no-aor-bench]\n' >&2
      printf '  [--skip-glibc-build]\n' >&2
      printf '  [--skip-glibc-benchmark-build]\n' >&2
      printf '  [--skip-all-benchmarks]\n' >&2
      printf 'Note: to change the benchmark family, modify the benchmarks array in the script source\n' >&2
      printf 'Note: The only reaason to ever use --skip-glibc-build or --skip-glibc-benchmark-build is if you are modifying this script itself\n' >&2
      exit 2
      ;;
  esac
done

# Run 5 times, then calculate the average
# Repeat the whole process 5 times and pick the best
# metrics from each group

if ! $skip_glibc_build; then
  # Build glibc
  echo "> Building glibc..."
  make -C /work/gnu/src/glibc-build \
    -j"$(nproc)"
else
  echo "> Skipping glibc build..."
fi

# Optionally skip the test
if $run_tests; then
  echo "> Running glibc tests..."
  make -C /work/gnu/src/glibc-build \
  test t=string/test-memset \
    -j"$(nproc)" 2>&1 |
  while IFS= read -r line; do
    printf '%s\n' "$line"
    if [[ $line == *"FAIL:"* ]]; then
        printf '\033[1;31m> Detected a FAIL: line in the glibc test output\033[0m\n' \
          >&2
        exit 1
    fi
  done
fi

# Run each benchmark individually five times and preserve every result.
benchmarks=(
  memset
  # memset-large
  # memset-random
  # memset-zero
  # memset-zero-large
)

routines=(
  # generic_memset
  __memset_aarch64_sve2 
  __memset_sve_zva64
  __memset_generic
)

if $skip_all_benchmarks; then
  routines=(
   __memset_aarch64_sve2 
  )
fi

# EC2 instance
results_root=/work/gnu/src/memset-results
# memset-results/\<date>-\<month>-\<year>/\<nanosecond>-\<second>-\<minute>-\<hour>
results_timestamp="$(TZ=Europe/London date +'%d-%m-%Y/%N-%S-%M-%H')"
results_dir="$results_root/$results_timestamp"
mkdir -p "${results_dir%/*}"
mkdir "$results_dir"

# Build all selected glibc benchmark binaries once.  The runs below execute
# those binaries directly through glibc's generated runtime wrapper.
if ! $skip_glibc_benchmark_build; then 
  printf '\033[1;36m> Building glibc benchmarks...\033[0m\n'
  make -C /work/gnu/src/glibc-build \
    bench-build \
    BENCHSET=string-benchset \
    "string-benchset=${benchmarks[*]}" \
    -j"$(nproc)"
else 
  printf '\033[1;36m> Skipping glibc benchmark build...\033[0m\n'
fi

for bench_run in {1..5}; do
  printf '\033[1;32m[%s/5] Running overall benchmark suite\033[0m\n' \
    "$bench_run"
  for benchmark in "${benchmarks[@]}"; do
    benchmark_binary="/work/gnu/src/glibc-build/benchtests/bench-$benchmark"

    # Run each routines benchmark 5 times, storing the results 1 by 1
    for run in {1..5}; do
      for routine in "${routines[@]}"; do
        routine_dir="$results_dir/bench_run-$bench_run/$routine"
        mkdir -p "$routine_dir"
        echo "[$run/5] Running $benchmark: $routine"
        GLIBC_BENCH_IMPL="$routine" \
          taskset -c 3 \
          /work/gnu/src/glibc-build/testrun.sh \
          "$benchmark_binary" \
          > "$routine_dir/run-$run.out"
      done
    done
  done
done

printf '\033[1;36m> Benchmark results saved in %s\033[0m\n' "$results_dir"

# Build the AoR benchmark
if $run_aor_benchmark; then
  printf '\033[1;36m> Building AoR benchmarks for memset...\033[0m\n'
  make -C /work/gnu/src/optimized-routines \
    ARCH=aarch64 \
    CFLAGS='-O2 -march=armv9-a+sve2' \
    build/bin/bench/memset

  printf '\033[1;36m> Running AoR benchmarks...\033[0m\n'
  # Run memset benchmarks 5 times
  taskset -c 3 \
    /work/gnu/src/optimized-routines/build/bin/bench/memset \
    > "$results_dir/aor-bench-memset.run-$run.out"

  printf '\033[1;36m> AoR benchmark results stored in %s\033[0m\n' \
    "$results_dir"
fi
