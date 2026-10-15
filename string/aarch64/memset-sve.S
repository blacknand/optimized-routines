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

ENTRY (__memset_aarch64_sve)
	dup	v0.16B, valw
	cmp	count, 16
	b.lo	L(set_16)

	/*
	TODO: While building predicate, get the size of the vector. Replace subsequent
	comparisons with the size of the vector. Then do not need to handle bytes < 32
	with VL 256.
	 */

	add	dstend, dstin, count
	cmp	count, 64
	b.hi	L(set_128)

	/* Set 16..64 bytes.  */
	mov	off, 48
	and	off, off, count, lsr 1
	sub	dstend2, dstend, off
	str	q0, [dstin]
	str	q0, [dstin, off]
	str	q0, [dstend2, -16]
	str	q0, [dstend, -16]
	ret

	.p2align 4
L(set_16):
	whilelo p0.b, xzr, count
	st1b	z0.b, p0, [dstin]
	ret

	.p2align 4
L(set_128):
	cmp	count, 128
	b.hi	L(set_long)
	stp	q0, q0, [dstin]
	stp	q0, q0, [dstin, 32]
	stp	q0, q0, [dstend, -64]
	stp	q0, q0, [dstend, -32]
	ret

	.p2align 4
L(set_long):
	/* Check if both dstin and count are multiples of 64. If both are,
	   beginning and tail store is not needed. */
	orr	x8, dstin, count
	and	x8, x8, 63
	cbz	x8, L(try_zva64)
	cmp	count, 384
	b.lo	L(no_zva)
L(try_zva64):
	tst	valw, 255
	b.ne	L(no_zva)

#ifndef SKIP_ZVA_CHECK
	mrs	zva_val, dczid_el0
	and	zva_val, zva_val, 31
	cmp	zva_val, 4		/* ZVA size is 64 bytes.  */
	b.ne	L(no_zva)
#endif
	/* Write first 64-bytes. */
	cbz 	x8, L(zva64_aligned)
	stp	q0, q0, [dstin]
	bic	dst, dstin, 31
	stp	q0, q0, [dst, 32]
	bic	dst, dstin, 63
	sub	count, dstend, dst	/* Count is now 64 too large.  */
	sub	count, count, 128	/* Adjust count and bias for loop.  */

	/* Write last 64-bytes. */
	stp	q0, q0, [dstend, -64]
	stp	q0, q0, [dstend, -32]
	b	L(zva64_setup)

L(zva64_aligned):
	sub 	dst, dstin, 64		/* Adjust for loops beginning writing from dst + 64. */
	.p2align 4
L(zva64_setup):
	/* If count < 256, zva64_loop cannot be used. */
	subs	count, count, 256
	b.lo	L(zva64_remainder)

	.p2align 4
L(zva64_loop):
	add	x11, dst, 64
	add	x12, dst, 128
	add	x13, dst, 192
	add	dst, dst, 256
	dc	zva, x11
	dc	zva, x12
	dc	zva, x13
	dc	zva, dst
	subs	count, count, 256
	b.hs	L(zva64_loop)

	.p2align 4
L(zva64_remainder):
	/* After adding back 256, if remainder is 0, exit. */
	adds	count, count, 256
	b.eq	L(zva_exit)
L(zva64_single_loop):
	add	dst, dst, 64
	dc	zva, dst
	subs	count, count, 64
	b.hi	L(zva64_single_loop)
L(zva_exit):
	ret

L(no_zva):
	bic	dst, dstin, 15
	str	q0, [dstin]
	sub	count, dstend, dst	/* Count is 16 too large.  */
	sub	count, count, 64 + 16	/* Adjust count and bias for loop.  */
L(no_zva_loop):
	stp	q0, q0, [dst, 16]
	stp	q0, q0, [dst, 48]
	add	dst, dst, 64
	subs	count, count, 64
	b.hi	L(no_zva_loop)
	stp	q0, q0, [dstend, -64]
	stp	q0, q0, [dstend, -32]
	ret

END (__memset_aarch64_sve)