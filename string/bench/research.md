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
+ ns/call

## Notes/points to consider
+ With the AoR benchmark, higher bytes/ns is better, but Codex says *do not interpret it as DRAM bandwidth: the benchmark repeatedly overwrites the same small region, so the data is hot in cache. Loop and function-call overhead are also included.*
+ I think there is a specific vector load to do...

I think the reason as to why there is different size handling throughout the program because the original engineer realised that certain sizes of memory can be filled in with specific instructions -- with the fills potentially overlapping. For example, with a fill value of `0` and a size big enough to execute `dc zva` instructions you can wipe out entire blocks of memory in a single go.

+ Two generated predicates and two `st1b` instructions are potentially more expensive than a single predicate and `st1b` instruction that crosses the page boundary in hardware. There is also no way to check whether a call will actually cross a page boundary so it may be that in the case of a page boundary, it is more optimal but when not page cross occurs it is more expensive. Only specifically benchmarking will work (Neoverse V2/V3 so just Graviton 4).

SVE2 will **not automatically** make memset faster. Speed will depend on:
  + store throughput
  + vector length
  + size distribution
  + alignment
  + cache state
  + memory bandwidth
  + if zero fills use `DC ZVA`

+ Zero-fills dominate `memset` calls so optimising for `dc zva` would be the best case/idea.

### Evgeny's idea
Yes. With SVE, two complementary predicates can ensure that neither individual store has active elements on both sides of the page boundary.

For a byte-granularity vector:

```asm
// x0     = destination
// x_len  = valid bytes in z0, no more than VL
// x_split = bytes from x0 to the next page boundary

whilelo p_all.b, xzr, x_len
whilelo p_lo.b,  xzr, x_split

// Restrict the low predicate to the valid region.
and     p_lo.b, p_all/z, p_lo.b, p_all.b

// Active valid lanes not included in p_lo.
bic     p_hi.b, p_all/z, p_all.b, p_lo.b

// Both retain the original lane-to-address mapping.
st1b    {z0.b}, p_lo, [x0]
st1b    {z0.b}, p_hi, [x0]
```

Using the same base address for both stores is important: lane `i` in `z0` still maps to `x0 + i`. If you instead advance the second store’s base to the page boundary, you must also shift or reorganize the vector so that the corresponding data moves into its low lanes.

For a power-of-two page size, the split distance is conceptually:

```text
bytes_to_boundary = (-address) & (page_size - 1)
```

Obtain the real page size from the operating system rather than assuming 4 KiB.

What this achieves:

- Inactive SVE lanes perform no memory access.
- Each `ST1B` accesses at most one page.
- If the whole vector lies before the boundary, `p_hi` is empty.
- If the destination begins on a boundary, `p_lo` is empty.
- The same idea works with `.h`, `.s`, or `.d`, provided the boundary and destination are suitably aligned for the element size.

Arm defines a separate address and memory access for each active SVE element, which is why predication can suppress the unwanted side’s accesses. See the [SVE memory model](https://developer.arm.com/documentation/ddi0487/latest/Part-B/AArch64-Application-Level-Architecture/AArch64-Application-Level-Memory-Model/About-the-Arm-memory-model/SVE-memory-model) and [Arm’s SVE introduction](https://developer.arm.com/-/media/Arm%20Developer%20Community/PDF/SVE%20programmers%20guide/102476_0001_00_en_introduction-to-sve.pdf).

Important limitations:

- You still touch two pages overall, so you still need two address translations and potentially two TLB/cache accesses.
- This is not fault-atomic. If the second page faults, the first store has already happened.
- It is not atomic with respect to other threads; they may observe the intermediate state.
- SVE has first-fault and non-faulting loads, but no corresponding fault-suppressing store.
- If your only goal is performance, processors already handle crossing stores internally; the additional predicates and second instruction might cost more. Benchmark both versions.

On Neoverse V2, SVE is only 128 bits, so this case occurs only when a vector begins within the final 15 bytes of a page. A common alternative is a short scalar/predicated prologue up to the boundary, followed by ordinary full-vector stores.

D = original destination
N = count
E = D + N
A = align_down(D, 16)
B = A + 16
M = min(B, E)

#### Examples
```
D = 4090
N = 10
E = 4100

A = align_down(4090, 16) = 4080
B = 4080 + 16           = 4096
M = min(4096, 4100)     = 4096

First range:  [D,M) = [4090,4096) — 6 bytes
Second range: [M,E) = [4096,4100) — 4 bytes
```

```
E = 4093
B = 4096
M = min(4096,4093) = 4093

So:
First range:  [4090,4093)
Second range: [4093,4093) — empty

Two essential correctness properties are:
D ≤ M ≤ E
[D,M) combined with [M,E) equals exactly [D,E)
```

## Questions
+ This implementation is for the AGI CPU, so why does `VL=256` matter since the processor is `VL=128`? My guess, is because at `VL=128` `memset` is faster on NEON rather than SVE/SVE2
+ How did the original programmer (probably Wilko) identify the size sections for the memset impls? How do you know `< 16`, `set_128`, etc.?
+ What are the most common cases for `memset`? Is there a way to see?
+ I am still so confused with what vector pipelines actually mean, how you know what type of vector load/store instructions to execute, how/why that matters, etc.

## Potentiall relevant commits
```bash
commit 163b1bbb76caba4d9673c07940c5930a1afa7548
Author: Wilco Dijkstra <wilco.dijkstra@arm.com>
Date:   Tue Dec 24 18:01:59 2024 +0000

    AArch64: Add SVE memset
    
    Add SVE memset based on the generic memset with predicated load for sizes < 16.
    Unaligned memsets of 128-1024 are improved by ~20% on average by using aligned
    stores for the last 64 bytes.  Performance of random memset benchmark improves
    by ~2% on Neoverse V1.
    
    Reviewed-by: Yury Khrustalev <yury.khrustalev@arm.com>

commit a08d9a52f967531a77e1824c23b5368c6434a72d
Author: Wilco Dijkstra <wilco.dijkstra@arm.com>
Date:   Mon Nov 25 18:43:08 2024 +0000

    AArch64: Remove zva_128 from memset
    
    Remove ZVA 128 support from memset - the new memset no longer
    guarantees count >= 256, which can result in underflow and a
    crash if ZVA size is 128 ([1]).  Since only one CPU uses a ZVA
    size of 128 and its memcpy implementation was removed in commit
    e162ab2bf1b82c40f29e1925986582fa07568ce8, remove this special
    case too.
    
    [1] https://sourceware.org/pipermail/libc-alpha/2024-November/161626.html
    
    Reviewed-by: Andrew Pinski <quic_apinski@quicinc.com>


commit cec3aef32412779e207f825db0d057ebb4628ae8
Author: Wilco Dijkstra <wilco.dijkstra@arm.com>
Date:   Mon Sep 9 15:26:47 2024 +0100

    AArch64: Optimize memset
    
    Improve small memsets by avoiding branches and use overlapping stores.
    Use DC ZVA for copies over 128 bytes.  Remove unnecessary code for ZVA sizes
    other than 64 and 128.  Performance of random memset benchmark improves by 24%
    on Neoverse N1.
    
    Reviewed-by: Adhemerval Zanella  <adhemerval.zanella@linaro.org>

commit 3d7090f14b13312320e425b27dcf0fe72de026fd
Author: Wilco Dijkstra <wilco.dijkstra@arm.com>
Date:   Thu Oct 26 17:07:21 2023 +0100

    AArch64: Add memset_zva64
    
    Add a specialized memset for the common ZVA size of 64 to avoid the
    overhead of reading the ZVA size.  Since the code is identical to
    __memset_falkor, remove the latter.
    
    Reviewed-by: Adhemerval Zanella  <adhemerval.zanella@linaro.org>

commit 5770c0ad1e0c784e817464ca2cf9436a58c9beb7
Author: Wilco Dijkstra <wdijkstr@arm.com>
Date:   Tue Nov 20 12:37:00 2018 +0000

    [AArch64] Adjust writeback in non-zero memset
    
    This fixes an ineffiency in the non-zero memset.  Delaying the writeback
    until the end of the loop is slightly faster on some cores - this shows
    ~5% performance gain on Cortex-A53 when doing large non-zero memsets.
    
            * sysdeps/aarch64/memset.S (MEMSET): Improve non-zero memset loop.

commit 5770c0ad1e0c784e817464ca2cf9436a58c9beb7
Author: Wilco Dijkstra <wdijkstr@arm.com>
Date:   Tue Nov 20 12:37:00 2018 +0000

    [AArch64] Adjust writeback in non-zero memset
    
    This fixes an ineffiency in the non-zero memset.  Delaying the writeback
    until the end of the loop is slightly faster on some cores - this shows
    ~5% performance gain on Cortex-A53 when doing large non-zero memsets.
    
            * sysdeps/aarch64/memset.S (MEMSET): Improve non-zero memset loop.

commit a8c5a2a9521e105da6e96eaf4029b8e4d595e4f5
Author: Wilco Dijkstra <wdijkstr@arm.com>
Date:   Thu May 12 16:41:00 2016 +0100

    This is an optimized memset for AArch64.  Memset is split into 4 main cases:
    small sets of up to 16 bytes, medium of 16..96 bytes which are fully unrolled.
    Large memsets of more than 96 bytes align the destination and use an unrolled
    loop processing 64 bytes per iteration.  Memsets of zero of more than 256 use
    the dc zva instruction, and there are faster versions for the common ZVA sizes
    64 or 128.  STP of Q registers is used to reduce codesize without loss of
    performance.
    
    The speedup on test-memset is 1% on Cortex-A57 and 8% on Cortex-A53.
    
            * sysdeps/aarch64/memset.S (__memset):
            Rewrite of optimized memset.
```