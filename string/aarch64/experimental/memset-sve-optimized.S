#include "asmdefs.h"

#define src     x0
#define dest    x3
#define countr  x2
#define value   w1

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
	mov	    dest, src
	cbz	    countr, L(done)

L(loop):
	strb	value, [dest], #1
	subs	countr, countr, #1
	b.ne	L(loop)

L(done):
	ret
END (__memset_sve_optimized)
