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

run_tests=true
run_aor_benchmark=true
skip_glibc_build=false
skip_glibc_benchmark_build=false
# run_neon=false
for arg in "$@"; do
  case $arg in
    --no-test) run_tests=false ;;
    --no-aor-bench) run_aor_benchmark=false ;;
    # --run-neon) run_neon=true ;;
    --skip-glibc-build) skip_glibc_build=true ;;
    --skip-glibc-benchmark-build) skip_glibc_benchmark_build=true ;;
    *)
      printf 'usage: %s [--no-test]\n' "$0" >&2
      printf '  [--no-aor-bench]\n' >&2
      printf '  [--run-neon (experimental)]\n' >&2
      printf '  [--skip-glibc-build]\n' >&2
      printf '  [--skip-glibc-benchmark-build]\n' >&2
      exit 2
      ;;
  esac
done

if ! $skip_glibc_build; then
  # Build glibc
  echo "Building glibc..."
  make -C /work/gnu/src/glibc-build \
    -j"$(nproc)"
else
  echo "Skipping glibc build"
fi

# Optionally skip the test
if $run_tests; then
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
  __memset_generic
  __memset_sve_optimized
)

# run neon implementation only once
# run the memset benchmark family individually for each implementation
# compare those benchmark results against each other
# just the family run for the python script
# 3.11% faster than the baseline strchr implementation being compared against
# average for all tests against the baseline; not the results for each run
# use the compiler baseline calcluations, etc.
# -25% is the best test case, so 25% better than the generic strchr implementation
# only calculate NEON once, then use those results to compare against my implementaion
# only build once, rather than building for every run

# strchr

results_root=/work/gnu/src/benchmark-results/memset-sve-optimized
results_dir="$results_root/$(LC_ALL=C date -u +%a-%d-%b-%M-%H-GMT)"
mkdir -p "$results_root"
mkdir "$results_dir"

# Build all selected glibc benchmark binaries once.  The runs below execute
# those binaries directly through glibc's generated runtime wrapper.
if ! $skip_glibc_benchmark_build; then 
  echo "Building glibc benchmarks..."
  make -C /work/gnu/src/glibc-build \
    bench-build \
    BENCHSET=string-benchset \
    "string-benchset=${benchmarks[*]}" \
    -j"$(nproc)"
else 
  echo "Skipping glibc benchmark build..."
fi

# TODO: Investigate a [--no-neon] flag where neon benchmarks are completely skipped
# and instead the current neon results are used. Note: this will require neon results
# to actually exist

for benchmark in "${benchmarks[@]}"; do
  benchmark_binary="/work/gnu/src/glibc-build/benchtests/bench-$benchmark"

  # Run each routines benchmark 5 times, storing the results 1 by 1
  for run in {1..5}; do
    for routine in "${routines[@]}"; do
      routine_dir="$results_dir/$routine"
      mkdir -p "$routine_dir"
      echo "Running $benchmark: $routine ($run/5)"
      GLIBC_BENCH_IMPL="$routine" \
        taskset -c 3 \
        /work/gnu/src/glibc-build/testrun.sh \
        "$benchmark_binary" \
        > "$routine_dir/bench-$benchmark.run-$run.out"
    done
  done
done

echo "Benchmark results saved in $results_dir"

# Build the AoR benchmark
if $run_aor_benchmark; then
  echo "Building AoR benchmarks for memset..."
  make -C /work/gnu/src/optimized-routines \
    ARCH=aarch64 \
    CFLAGS='-O2 -march=armv9-a+sve2' \
    build/bin/bench/memset

  echo "Running AoR benchmarks..."
  # Run memset benchmarks 5 times
  for run in {1..5}; do
    echo "Running benchmark ($run/5)"
    taskset -c 3 \
      /work/gnu/src/optimized-routines/build/bin/bench/memset \
      > "$results_dir/aor-bench-memset.run-$run.out"
  done

  echo "AoR benchmark results stored in $results_dir"
fi
