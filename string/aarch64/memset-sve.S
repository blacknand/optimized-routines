/*
 * memset - fill memory with a constant byte
 *
 * Copyright (c) 2024-2024, Arm Limited.
 * SPDX-License-Identifier: MIT OR Apache-2.0 WITH LLVM-exception
 */

/* Assumptions:
 *
 * ARMv8-a, AArch64, Advanced SIMD, SVE, unaligned accesses.
 *
 */

#include "asmdefs.h"

.arch armv8-a+sve

#define dstin	x0
#define val	x1
#define valw	w1
#define count	x2
#define dst	x3
#define dstend	x4
#define zva_val	x5
#define vlen	x5
#define off	x3
#define dstend2 x5
#define dstp	x6
#define xN	x7
#define count2  x9

ENTRY (__memset_aarch64_sve)
	dup	z0.b, valw

	whilelo p0.b, xzr, count
	st1b	z0.b, p0, [dstin]

	cmp count, 16
	b.ls	L(return)

	/* Potentially unecessary to use cntb. */
	cntp xN, p0, p0.b
	sub count2, count, xN
	add dstp, dstin, xN

	/* dstp should enable the other paths to avoid writing the first 16
	   bytes, and the size of the vector is not calculated anymore. */

	/* The problem is the program writes the first 16 bytes,
	   and then falls through to the 16..64 path and attempts to write from there.

	   If the program has written the first 16 bytes and there are not enough bytes
	   left over to actually fall through, then it causes a segfault. */

	/* Two potential fixes:
		+ Overwrite 16 bytes in 16..64, ignore in every other path
		+ Handle the remaining n bytes in a code block which is branched to
	 */

	add	dstend, dstin, count
	cmp	count2, 64
	b.hi	L(set_128)

	/* 16..64 */
	mov	off, 48
	and	off, off, count2, lsr 1
	sub	dstend2, dstend, off
	whilelo p1.b, off, count2
	st1b z0.b, p1, [dstp]
	st1b z0.b, p1, [dstp, off]
	str	q0, [dstend2, -16]
	str	q0, [dstend, -16]
	ret

L(return):
	ret

.p2align 4
L(set_128):
	bic	dst, dstp, 15
	cmp	count2, 128
	b.hi	L(set_long)
	stp	q0, q0, [dstp]
	stp	q0, q0, [dstp, 32]
	stp	q0, q0, [dstend, -64]
	stp	q0, q0, [dstend, -32]
	ret

.p2align 4
L(set_long):
	cmp	count2, 256
	b.lo	L(no_zva)
	tst	valw, 255
	b.ne	L(no_zva)

#ifndef SKIP_ZVA_CHECK
	mrs	zva_val, dczid_el0
	and	zva_val, zva_val, 31
	cmp	zva_val, 4		/* ZVA size is 64 bytes.  */
	b.ne	L(no_zva)
#endif
	str	q0, [dstp]
	str	q0, [dst, 16]
	bic	dst, dstp, 31
	stp	q0, q0, [dst, 32]
	bic	dst, dstp, 63
	sub	count2, dstend, dst	/* Count is now 64 too large.  */
	sub	count2, count2, 128	/* Adjust count and bias for loop.  */

	sub	x8, dstend, 1		/* Write last bytes before ZVA loop.  */
	bic	x8, x8, 15
	stp	q0, q0, [x8, -48]
	str	q0, [x8, -16]
	str	q0, [dstend, -16]

.p2align 4
L(zva64_loop):
	add	dst, dst, 64
	dc	zva, dst
	subs	count2, count2, 64
	b.hi	L(zva64_loop)
	ret

L(no_zva):
	str	q0, [dstp]
	sub	count2, dstend, dst	/* Count is 16 too large.  */
	sub	count2, count2, 64 + 16	/* Adjust count and bias for loop.  */
L(no_zva_loop):
	stp	q0, q0, [dst, 16]
	stp	q0, q0, [dst, 48]
	add	dst, dst, 64
	subs	count2, count2, 64
	b.hi	L(no_zva_loop)
	stp	q0, q0, [dstend, -64]
	stp	q0, q0, [dstend, -32]
	ret

END (__memset_aarch64_sve)
