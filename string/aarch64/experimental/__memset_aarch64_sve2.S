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
#define dest  	   x3	// beginning destination for fill
#define destend    x4	// end destination

.arch armv9-a+sve2

ENTRY (__memset_aarch64_sve2)
	/* TODO: think about the correct load given the size of the vector + number of vectors
	   for whatever core this is */

	/* TODO: Investigate if there is a better way to branch? */
	cbz count, null_count

	dup v0.16B, valw		
	add dstend, destin, count
	/* TODO: Investigate how to check if the alignemnt is near 4096 with a count of < 16 */
	cmp count, 16

    /* Set 16..64 bytes.  */
    mov	off, 48
    and	off, off, count, lsr 1
    sub	dstend2, dstend, off
    str	q0, [dstin]
    str	q0, [dstin, off]
    str	q0, [dstend2, -16]
    str	q0, [dstend, -16]
    ret
	b.lo L(set_16)

/* 
TODO: Implement DC ZVA blocks
L(zva64_loop):
	dc zva, dst
	subs count, count, 64
	b.hi 	L(zva64_loop)
	ret
*/

L(null_count):
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
	whilelo p1.b, dest, dstend

	/* Use same vector registers, different predicates and different base addresses */
	st1b	z0.b, p0, [destin]		
	st1b	z0.b, p1, [dest]		
	ret

END (__memset_aarch64_sve2)
