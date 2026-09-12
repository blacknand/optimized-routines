/*
Assumptions:
	+ Armv9.2-A
	+ AArch64
	+ SVE/SVE2
	+ NEON
	+ ZVA size is 64
	+ Unaligned access
 */

#include "asmdefs.h"

#define destin     x0	// source destination
#define val   	   x1	// fill value
#define valw  	   w1
#define count	   x2
#define dest  	   x3	// beginning destination for fil
#define off		   x3
#define destend    x4	// end destination
#define destend2   x5	

.arch armv9-a+sve2

/*
Investigation TODOs:
	+ cache-line
	+ how to check if near a boundary of any kind (page, cache-line, anything else)
	+ where to handle count == 0
Questions:
	+ More loop unrolling, or has Wilko done all of it?
	+ Why is this specifically SVE2? There must be some SVE2 instructions I can use that
		will optimise? (reduce the number of lines)
Notes:
	+ VL = 128, store throughput is one of the most important factors
	+ Size distribution is a huge factor?
	+ alignment + cache state (if that includes cache-line?)
	+ Memory bandwidth
	+ optimise for DC ZVA, Wilko has most likely already exploited this
	+ Perf: Wilko was talking about the total number of instructions used when executing a
		routine, including the instructions for setting the system up, etc.
*/

ENTRY (__memset_aarch64_sve2)
	/* TODO: Measure just an immediate cbz (only instruction) against ZVA64 version */
	cbz count, L(null_count)

	/* 16 lanes, each 8 bits wide */
	dup v0.16B, valw		
	add destend, destin, count
	cmp count, 16
	b.lo	L(set_16)

	cmp	count, 64
	b.hi	L(set_128)

    /* Set 16..64 bytes.  */
    mov	off, 48
    and	off, off, count, lsr 1
    sub	destend2, destend, off
    str	q0, [destin]
    str	q0, [destin, off]
    str	q0, [destend2, -16]
    str	q0, [destend, -16]
    ret

.p2align 4
L(set_16):
	// cbz count, L(null_count)

	// bic dest, destin, 15				/* Align down destin to a 16-byte address */
	// add dest, dest, 16
	// cmp dest, destend
	// /* dest is the split point: if the requested region crosses the next 16-byte boundary,
		// dest is that boundary. If it does not cross, then dest is simply the end. */
	// csel dest, dest, destend, lo		

	// /* Generate the first predicate from the original source up to the split, and then
		// generate the second predicate from the split until the destination. */
	// whilelo p0.b, destin, dest
	// whilelo p1.b, dest, destend

	// /* Use same vector registers, different predicates and different base addresses */
	// st1b	z0.b, p0, [destin]		
	// st1b	z0.b, p1, [dest]		
	// ret

	whilelo p0.b, xzr, count				/* xzr is a zero-register, any data written to it is discarded */
	st1b	z0.b, p0, [destin]				/* Predicated contiguous store? */
	ret

.p2align 4
L(set_128):
	bic	dest, destin, 15
	cmp	count, 128
	b.hi	L(set_long)
	stp	q0, q0, [destin]					
	stp	q0, q0, [destin, 32]				
	stp	q0, q0, [destend, -64]			
	stp	q0, q0, [destend, -32]			
	ret

L(set_long):
	/* ZVA is only used when count > 256 to justify the setup for it,
		ensuring there is enough work */
	cmp	count, 256
	b.lo	L(no_zva)
	/* Check whether valw is a multiple of 256? 
	   if ((valw & 0xFF) != 0) goto no_zva */
	tst	valw, 255
	b.ne	L(no_zva)

	str	q0, [destin]
	str	q0, [dest, 16]
	/* dest = destin & ~31 so the lowest 5 bits of destin are cleared */
	bic	dest, destin, 31
	stp	q0, q0, [dest, 32]
	bic	dest, destin, 63
	sub	count, destend, dest	/* Count is now 64 too large.  */
	sub	count, count, 128	/* Adjust count and bias for loop.  */

	sub	x8, destend, 1		/* Write last bytes before ZVA loop.  */
	bic	x8, x8, 15
	stp	q0, q0, [x8, -48]
	str	q0, [x8, -16]
	str	q0, [destend, -16]

/* .p2align 4 */
L(zva64_loop):
	add	dest, dest, 64
	dc zva, dest
	subs count, count, 64
	b.hi 	L(zva64_loop)
	ret

L(no_zva):
	str	q0, [destin]				
	sub	count, destend, dest		/* Count is 16 too large.  */
	sub	count, count, 64 + 16	/* Adjust count and bias for loop.  */

L(no_zva_loop):
	stp	q0, q0, [dest, 16]
	stp	q0, q0, [dest, 48]
	add	dest, dest, 64
	subs	count, count, 64
	b.hi	L(no_zva_loop)
	stp	q0, q0, [destend, -64]
	stp	q0, q0, [destend, -32]
	ret

L(null_count):
	ret

END (__memset_aarch64_sve2)
