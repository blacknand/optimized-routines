/*
Assumptions:
	+ Armv9.2-A
	+ AArch64
	+ SVE/SVE2
	+ NEON
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

ENTRY (__memset_aarch64_sve2)
	/* TODO: think about the correct load given the size of the vector + number of vectors
	   for whatever core this is */

	/* TODO: Investigate if there is a better way to branch? */
	cbz count, L(null_count)

	/* Note: V2 cores have 4 SIMD pipelines, so why does this duplicate store not
		use 4 32-bit fields per vector instead? */
	dup v0.16B, valw		
	add destend, destin, count
	/* TODO: Investigate how to check if the alignemnt is near 4096 with a count of < 16 */
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
	bic dest, destin, 15				/* Align down destin to a 16-byte address */
	add dest, dest, 16
	cmp dest, destend
	/* dest is the split point: if the requested region crosses the next 16-byte boundary,
		dest is that boundary. If it does not cross, then dest is simply the end. */
	csel dest, dest, destend, lo		

	/* Generate the first predicate from the original source up to the split, and then
		generate the second predicate from the split until the destination. */
	whilelo p0.b, destin, dest
	whilelo p1.b, dest, destend

	/* Use same vector registers, different predicates and different base addresses */
	st1b	z0.b, p0, [destin]		
	st1b	z0.b, p1, [dest]		
	ret

.p2align 4
L(set_128):
	bic	dest, destin, 15
	cmp	count, 128
	b.hi	L(set_long)
	stp	q0, q0, [destin]					// [destin, destin + 32)
	stp	q0, q0, [destin, 32]				// [destin, destin + 64]
	stp	q0, q0, [destend, -64]			// [destend - 64, destend - 32)
	stp	q0, q0, [destend, -32]			// [destend - 32, destend)
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
