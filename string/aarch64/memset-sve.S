/*
 * memset - fill memory with a constant byte
 *
 * Copyright (c) 2024-2024, Arm Limited.
 * SPDX-License-Identifier: MIT OR Apache-2.0 WITH LLVM-exception
 */

/* Assumptions:
 *
 * ARMv9.2-a, AArch64, Advanced SIMD, SVE, unaligned accesses.
 * SVE2.
 */

#include "asmdefs.h"

.arch armv9.2-a+sve2

#define dstin		x0
#define val			x1
#define valw		w1
#define count		x2
#define dst			x3
#define dstend		x4
#define off			x3
#define zva_val	    x5
#define dstend2 	x5

ENTRY (__memset_aarch64_sve)
	cbz count, L(null_count)

	/* Duplicate low byte of valw across the vector. */
	dup	v0.16B, valw
	add	dstend, dstin, count
	cmp	count, 16
	b.lo	L(set_16)

	cmp	count, 64
	b.hi	L(set_128)

	/* Set 16..64 bytes. */
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
	/* Align dst down to a 16-byte address. */
	bic	dst, dstend, 0xf
	cmp	dst, dstin
	/* dst = max(dstin, align_down(dstend, 16)),
	   dst is then used to work out the split point. */
	csel dst, dst, dstin, hs				

	/* Using dst, generate two predicates from dstin to dst,
	   and then dst to dstend. If there is a page boundary, this
	   prevents a single write from crossing the page boundary.
	   
	   One or both of the predicates could be used to perform a write. */
	whilelo p0.b, dstin, dst
	whilelo p1.b, dst, dstend
	st1b	z0.b, p0, [dstin]
	st1b	z0.b, p1, [dst] 
	ret

.p2align 4
L(set_128):
	bic	dst, dstin, 15
	cmp	count, 128
	b.hi	L(set_long)
	stp	q0, q0, [dstin]
	stp	q0, q0, [dstin, 32]
	stp	q0, q0, [dstend, -64]
	stp	q0, q0, [dstend, -32]
	ret

.p2align 4
L(set_long):
	cmp	count, 256
	b.lo	L(no_zva)
	tst	valw, 255
	b.ne	L(no_zva)

#ifndef SKIP_ZVA_CHECK
	mrs	zva_val, dczid_el0
	and	zva_val, zva_val, 31
	cmp	zva_val, 4						/* ZVA size is 64 bytes.  */
	b.ne	L(no_zva)
#endif
	str	q0, [dstin]
	str	q0, [dst, 16]
	bic	dst, dstin, 31
	stp	q0, q0, [dst, 32]
	bic	dst, dstin, 63
	sub	count, dstend, dst				/* Count is now 64 too large. */
	sub	count, count, 128				/* Adjust count and bias for loop. */

	sub	x8, dstend, 1					/* Write last bytes before ZVA loop. */
	bic	x8, x8, 15
	stp	q0, q0, [x8, -48]
	str	q0, [x8, -16]
	str	q0, [dstend, -16]

.p2align 4
L(zva64_loop):
	add	dst, dst, 64
	dc	zva, dst
	subs	count, count, 64
	b.hi	L(zva64_loop)
	ret

L(no_zva):
	str	q0, [dstin]
	sub	count, dstend, dst				/* Count is 16 too large. */
	sub	count, count, 64 + 16			/* Adjust count and bias for loop. */

L(no_zva_loop):
	stp	q0, q0, [dst, 16]
	stp	q0, q0, [dst, 48]
	add	dst, dst, 64
	subs	count, count, 64
	b.hi	L(no_zva_loop)
	stp	q0, q0, [dstend, -64]
	stp	q0, q0, [dstend, -32]
	ret

L(null_count):
	ret

END (__memset_aarch64_sve)
