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
// TODO: investigate which macros I can remove (if they decrease performance).
#define xN	x7
#define count2  x9

ENTRY (__memset_aarch64_sve)
	dup	z0.b, valw

	whilelo p0.b, xzr, count
	st1b	z0.b, p0, [dstin]

	cmp count, 16
	b.ls	L(return)

	/* The first SVE store has written at least 16 bytes.  */
	add	dstend, dstin, count
	sub count2, count, 16
	add dstp, dstin, 16
	cmp	count2, 64
	b.hi	L(set_128)


	/* Up to 64 bytes remain after the initial store.  */
	cmp count2, 32
	b.ls L(tmp)

	mov	off, 48
	and	off, off, count2, lsr 1
	whilelo p1.b, off, count2
	sub	dstend2, dstend, off
	st1b z0.b, p1, [dstp]
	st1b z0.b, p1, [dstp, off]
	str	q0, [dstend2, -16]
	str	q0, [dstend, -16]
	ret

L(tmp):
	whilelo p1.b, xzr, count2
	st1b z0.b, p1, [dstp]
	str	q0, [dstend, -16]
	ret

L(return):
	ret

.p2align 4
L(set_128):
	cmp	count2, 128
	b.hi	L(set_long)
	stp	q0, q0, [dstp]
	/* The first 32 bytes and final 64 bytes cover up to 96 bytes.  */
	cmp	count2, 96
	b.ls	L(set_112_tail)
	stp	q0, q0, [dstp, 32]
L(set_112_tail):
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
	bic	dst, dstp, 15
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
	bic	dst, dstin, 15
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
