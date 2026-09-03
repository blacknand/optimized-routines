## Modification
+ Modify `glibc/benchtests/bench-memset.c -> test_main()` to modify the memset parameters for glibc
+ Modify `optimized-routines/string/bench/memset.c -> memset_medium()` to modify the medium benchmark family

## `alignment=0`
```bash
Medium memset (bytes/ns):
                memset 8B:  7.46 16B: 14.91 32B: 14.07 64B: 14.62 128B: 55.74 256B: 100.71 512B: 118.86 
      __memset_aarch64 8B:  7.45 16B: 17.88 32B: 14.91 64B: 29.82 128B: 59.63 256B: 102.14 512B: 129.39 
       __memset_scalar 8B:  7.46 16B: 12.84 32B: 14.91 64B: 29.81 128B: 54.36 256B: 102.18 512B: 129.52 
  __memset_aarch64_sve 8B: 11.18 16B: 17.88 32B: 14.91 64B: 29.82 128B: 59.64 256B: 101.88 512B: 128.75 
```

## `alignment=4095`
```bash
Medium memset (bytes/ns):
                memset 8B:  2.03 16B:  0.97 32B:  3.41 64B:  6.78 128B: 24.86 256B: 44.48 512B: 78.86 
      __memset_aarch64 8B:  1.09 16B:  0.96 32B:  3.91 64B: 14.24 128B: 27.46 256B: 34.43 512B: 67.70 
       __memset_scalar 8B:  1.02 16B:  1.00 32B:  3.66 64B: 13.47 128B: 25.71 256B: 35.24 512B: 67.76 
  __memset_aarch64_sve 8B:  1.98 16B:  0.94 32B:  4.33 64B: 14.04 128B: 27.42 256B: 45.61 512B: 79.50 
```

## glibc variable alignment
```bash
Comparison
  Candidate: __memset_sve_zva64
  Baseline:  __memset_generic
  Negative percentages mean the candidate is faster.
  Positive percentages mean the candidate is slower.

Individual runs
  Mean of the per-test differences in each matching run pair.
  Run 1: -7.93% (candidate faster)
  Run 2: -8.02% (candidate faster)
  Run 3: -9.50% (candidate faster)
  Run 4: -8.05% (candidate faster)
  Run 5: -9.80% (candidate faster)

Overall benchmark family
  Each test uses the median timing from 5 runs; 10 tests total.
  Average difference: -8.09% (candidate faster)
  Winning tests: 8/10 (80.00%)
  Best test: -40.38% (candidate faster)
  Worst test: +120.15% (candidate slower)

Worst 5 tests across all runs
  Ranked by percentage difference using median timings from 5 runs.
  1. Test 7: +120.15% (candidate slower); length=3, alignment=4095, char=0
  2. Test 6: +116.46% (candidate slower); length=2, alignment=4095, char=0
  3. Test 1: -37.25% (candidate faster); length=2, alignment=0, char=0
  4. Test 10: -39.95% (candidate faster); length=3, alignment=2001, char=0
  5. Test 5: -39.96% (candidate faster); length=1, alignment=4095, char=0

Worst 5 individual results across all runs
  Ranked by percentage difference between matching candidate and baseline results.
  1. Run 5, test 7: +134.20% (candidate slower); length=3, alignment=4095, char=0
  2. Run 3, test 7: +130.08% (candidate slower); length=3, alignment=4095, char=0
  3. Run 1, test 7: +120.18% (candidate slower); length=3, alignment=4095, char=0
  4. Run 2, test 7: +120.14% (candidate slower); length=3, alignment=4095, char=0
  5. Run 4, test 7: +120.11% (candidate slower); length=3, alignment=4095, char=0
```
From the above, it is clear that when memset is called with `alignment=4095` it is much slower. This applies to all memset routines, **but there is something else which I cannot remember. Investigate + research further.** 

## AoR `memset` medium benchmark metrics
+ Bytes per nanosecond: `(bytes/call * calls) / nanoseconds` where `size = bytes/call`
+ 

## Notes/points to consider
+ With the AoR benchmark, higher bytes/ns is better, but Codex says *do not interpret it as DRAM bandwidth: the benchmark repeatedly overwrites the same small region, so the data is hot in cache. Loop and function-call overhead are also included.*

## Questions
+ What does the AoR benchmark output mean?
+ How can I further tweak the AoR benchmark?
+ How much does the size/count actually matter?