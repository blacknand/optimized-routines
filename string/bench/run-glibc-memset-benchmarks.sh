#!/usr/bin/env bash

# TODO: Register __memset_aarch64_sve from memset-sve.S into glibc infra

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

# Copy memset-optimized-sve.S into glibc and update the headers + retain ENTRY/END (__memset_sve_optimized)
# Note that this is a new memset implementation, it does not replace the existing memset implementations (sve, generic SIMD, zva, etc.)
sve_source=/work/gnu/src/optimized-routines/string/aarch64/experimental/memset-sve-optimized.S
sve_glibc=/work/gnu/src/glibc/sysdeps/aarch64/multiarch/memset_sve_optimized.S

# Only update the glibc copy when its transformed contents have changed.  This
# avoids forcing an otherwise unnecessary glibc rebuild on every script run.
if ! cmp -s \
  <(sed 's|^#include "asmdefs.h"$|#include <sysdep.h>|' "$sve_source") \
  "$sve_glibc"; then
  sed 's|^#include "asmdefs.h"$|#include <sysdep.h>|' \
    "$sve_source" > "$sve_glibc"
fi

# Register the implementation with the build
if ! grep -Fq 'memset_sve_optimized' /work/gnu/src/glibc/sysdeps/aarch64/multiarch/Makefile; then
  # Insert the text before the memset_sve_zva64 line
  sed -i '/^[[:space:]]*memset_sve_zva64 \\/i\  memset_sve_optimized \\' /work/gnu/src/glibc/sysdeps/aarch64/multiarch/Makefile
fi

# Test and benchmark registration
if ! grep -Fq '__memset_sve_optimized' /work/gnu/src/glibc/sysdeps/aarch64/multiarch/ifunc-impl-list.c; then
  # Insert the text before the __memset_sve_zva64 line
  sed -i '/__memset_sve_zva64)/i\              IFUNC_IMPL_ADD (array, i, memset, sve2, __memset_sve_optimized)' /work/gnu/src/glibc/sysdeps/aarch64/multiarch/ifunc-impl-list.c
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

# TODO: add an option to only build and run tests for the modified memset.
# For example, if I make a change to __memset_sve_optimized and I am benchmarking against __memset_generic,
# then I will not be making any changes to __memset_generic so there is no point in building and benchmarking
# __memset_generic. I should only test, build and benchmark routines where there has actually been a change.

# NOTE: does make actually cache anything? Like with CMake, I am pretty sure if I build and then build again with no
# changes it should still be really quick because CMake caches everything. Else, do something to save time with building...

# TODO: Add flag to skip running benchmarks for every memset other than __memset_sve_optimized

# TODO: List the top 5 worst cases and the parameters they use

run_tests=true
run_aor_benchmark=true
skip_glibc_build=false
skip_glibc_benchmark_build=false
skip_all_benchmarks=true
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
  -j"$(nproc)"
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
  generic_memset
  __memset_sve_optimized
  __memset_sve_zva64
  __memset_generic
)

if $skip_all_benchmarks; then
  routines=(
    __memset_sve_optimized
  )
fi

results_root=/work/gnu/src/benchmark-results/memset-sve-optimized
results_dir="$results_root/$(LC_ALL=C date -u +%a-%d-%b-%M-%H-GMT)"
mkdir -p "$results_root"
mkdir "$results_dir"

# Build all selected glibc benchmark binaries once.  The runs below execute
# those binaries directly through glibc's generated runtime wrapper.
if ! $skip_glibc_benchmark_build; then 
  echo "> Building glibc benchmarks..."
  make -C /work/gnu/src/glibc-build \
    bench-build \
    BENCHSET=string-benchset \
    "string-benchset=${benchmarks[*]}" \
    -j"$(nproc)"
else 
  echo "> Skipping glibc benchmark build..."
fi

for benchmark in "${benchmarks[@]}"; do
  benchmark_binary="/work/gnu/src/glibc-build/benchtests/bench-$benchmark"

  # Run each routines benchmark 5 times, storing the results 1 by 1
  for run in {1..5}; do
    for routine in "${routines[@]}"; do
      routine_dir="$results_dir/$routine"
      mkdir -p "$routine_dir"
      echo "[$run/5] Running $benchmark: $routine"
      GLIBC_BENCH_IMPL="$routine" \
        taskset -c 3 \
        /work/gnu/src/glibc-build/testrun.sh \
        "$benchmark_binary" \
        > "$routine_dir/bench-$benchmark.run-$run.out"
    done
  done
done

echo "> Benchmark results saved in $results_dir"

# Build the AoR benchmark
if $run_aor_benchmark; then
  echo "> Building AoR benchmarks for memset..."
  make -C /work/gnu/src/optimized-routines \
    ARCH=aarch64 \
    CFLAGS='-O2 -march=armv9-a+sve2' \
    build/bin/bench/memset

  echo "Running AoR benchmarks..."
  # Run memset benchmarks 5 times
  for run in {1..5}; do
    echo "[$run/5] Running benchmark "
    taskset -c 3 \
      /work/gnu/src/optimized-routines/build/bin/bench/memset \
      > "$results_dir/aor-bench-memset.run-$run.out"
  done

  echo "> AoR benchmark results stored in $results_dir"
fi
