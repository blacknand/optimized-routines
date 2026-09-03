/*
Assumptions:
	+ SVE
	+ SVE2
	+ Advanced SIMD (NEON)
	+ AArch64
	+ Armv9.2-A (NeoverseV3/NeoverseV3AE)
	+ Page size of 4 KiB (4096 bytes)
 */

#include "asmdefs.h"

#define src   	   x0
#define val   	   x1
#define valw  	   w1
#define count	   x2
#define dest  	   x3
#define destend    x3

/* .arch armv8-a+sve */

/*
  SVE2 will not automatically make memset faster. Speed will depend on:
	+ store throughput
	+ vector length
	+ size distribution
	+ alignment
	+ cache state
	+ memory bandwidth
	+ if zero fills use DC ZVA
 */

ENTRY (__memset_sve_optimized)
	// dup v0.16B, valw
	// /* TODO: Switch over to use vectors and predicates */
	// /* TODO: if count < 16 */
	// cmp count, 16
	// b.lo	L(set_16)

// /*
// L(loop):
	// strb	value, [dest], #1
	// subs	countr, countr, #1
	// b.ne	L(loop)
// */

// L(set_16):
	// /* Generate a predicate where count lanes are true and use the predicate
	   // to store a byte in the corresponding lane within z0 */
	// whilelo p0.b, xzr, count
	// st1b	z0.b, p0, [src]
	// ret
END (__memset_sve_optimized)
