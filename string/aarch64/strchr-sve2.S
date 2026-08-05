/*
 * strchr/strchrnul - find a character in a string.
 *
 * Copyright (c) 2026, Arm Limited.
 * SPDX-License-Identifier: MIT OR Apache-2.0 WITH LLVM-exception
 */

#include "asmdefs.h"

/* Assumptions: SVE2 (not MTE compatible).  */

.arch armv9-a+sve2

/* To build as strchrnul, define BUILD_STRCHRNUL before compiling this file.  */
#if defined (BUILD_STRCHRNUL)
# define FUNC  __strchrnul_aarch64_sve2
#else
# define FUNC  __strchr_aarch64_sve2
#endif

#define src		x0
#define chrin		w1
#define result		x0

#define	vlalign		x2
#define	tmp		x3

#define zdata		z0
#define zchr_nul	z1		/* Search vector with chrin and NUL.  */

#define pall		p0
#define pchr_nul	p1		/* MATCH result predicate.  */
#define pchr		p2		/* Compare result with chrin.  */
#define psrc		p3		/* Chars before vlalign boundary.  */
#define pindex		p4		/* Mask for index of match.  */

ENTRY (FUNC)
	ptrue	pall.b
	and	chrin, chrin, 0xff
	dup	zchr_nul.h, chrin	/* Search vector with chrin and NUL.  */

	and	tmp, src, 0xfff		/* Pagecross check for 2*VL reads.  */
	incb	tmp, all, mul #2
	tbnz	tmp, 12, L(pagecross)

	ld1b	{zdata.b}, pall/z, [src]
	match	pchr_nul.b, pall/z, zdata.b, zchr_nul.b
	b.any	L(firstmatch)
	ld1b	{zdata.b}, pall/z, [src, 1, mul vl]
	match	pchr_nul.b, pall/z, zdata.b, zchr_nul.b
	b.none	L(loop_start)
	incb	src
L(firstmatch):
	brkb	pindex.b, pall/z, pchr_nul.b	/* Mask chars before match.  */
	incp	src, pindex.b			/* Get index of match.  */
#if !defined (BUILD_STRCHRNUL)
	cbz	chrin, 1f			/* Special case NUL chrin.  */
	cmpne	pchr.b, pchr_nul/z, zdata.b, 0	/* Check we matched chrin.  */
	csel	result, src, xzr, first		/* Return match or NULL.  */
1:	ret
	nop
#else
	ret
#endif
L(loop_start):
	mov	vlalign, 0
	decb	vlalign
	and	src, src, vlalign		/* Align src to VL.  */

	.p2align 4
L(loop):
	ld1b	{zdata.b}, pall/z, [src, 2, mul vl]
	incb	src, all, mul #2
	match	pchr_nul.b, pall/z, zdata.b, zchr_nul.b
	b.any	L(loop_end)
L(loop2):
	ld1b	{zdata.b}, pall/z, [src, 1, mul vl]
	match	pchr_nul.b, pall/z, zdata.b, zchr_nul.b
	b.none	L(loop)
	incb	src
L(loop_end):
	brkb	pindex.b, pall/z, pchr_nul.b	/* Mask chars before match.  */
	incp	src, pindex.b			/* Get index of match.  */
#if !defined (BUILD_STRCHRNUL)
	cbz	chrin, 2f			/* Special case NUL chrin.  */
	cmpne	pchr.b, pchr_nul/z, zdata.b, 0	/* Check we matched chrin.  */
	csel	result, src, xzr, first		/* Return match or NULL.  */
#endif
2:	ret

	.p2align 3
L(pagecross):
	mov	vlalign, 0
	decb	vlalign
	orn	tmp, src, vlalign		/* End of VL aligned src.  */
	whilels	psrc.b, src, tmp		/* Mask of valid src chars.  */
	ld1b	{zdata.b}, psrc/z, [src]
	match	pchr_nul.b, psrc/z, zdata.b, zchr_nul.b
	b.any	L(firstmatch)
	and	src, src, vlalign		/* Align src to VL.  */
	b	L(loop2)
END (FUNC)
