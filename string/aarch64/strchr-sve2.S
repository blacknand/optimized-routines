/*
 * strchr/strchrnul - find a character in a string
 *
 * Copyright (c) 2026, Arm Limited.
 * SPDX-License-Identifier: MIT OR Apache-2.0 WITH LLVM-exception
 */

#include "asmdefs.h"

.arch armv9-a+sve2

/* Assumptions:
 *
 * AArch64
 * SVE2 Available.
 */

// To build as strchrnul, define BUILD_STRCHRNUL before compiling this file.
#if defined (BUILD_STRCHRNUL)
#define FUNC  __strchrnul_aarch64_sve2
#else
#define FUNC  __strchr_aarch64_sve2
#endif

#define chrin		w1		// int chr.
#define result		x0		// Return.

#define src		x0		// Current data pointer.
#define	vlalign		x2		// Alignment mask.
#define	tmp		x3

#define zdata		z0		// Data.
#define zchr_nul	z1		// chr and NUL data for search.

#define pall		p0		// All active predicate.
#define pchr_nul	p1		// chr and NUL search result.
#define pchr		p2		// chr search result.
#define psrc		p3		// Mask of chars before srcin.
#define pfirst		p4		// First found.

ENTRY (FUNC)
	ptrue	pall.b
	and	chrin, chrin, 0xff	// Set zeros after first byte.
	dup	zchr_nul.h, chrin	// Initialize chr and NUL for search.

	and	tmp, src, 0xfff		// Check for pagecross of 2VL reads.
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
	brkb	pfirst.b, pall/z, pchr_nul.b	// Find first element.
	incp	src, pfirst.b			// Increment by element index.
#if !defined (BUILD_STRCHRNUL)
	cbz	chrin, 1f			// Special case NUL chrin.
	cmpne	pchr.b, pchr_nul/z, zdata.b, 0	// Matched chrin?
	csel	result, src, xzr, first		// If it is NUL, return null.
1:	ret
	nop
#else
	ret
#endif
L(loop_start):
	mov	vlalign, 0
	decb	vlalign
	and	src, src, vlalign		// Align src to VL.
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
	brkb	pfirst.b, pall/z, pchr_nul.b	// Find first element.
	incp	src, pfirst.b			// Increment by element index.
#if !defined (BUILD_STRCHRNUL)
	cbz	chrin, 2f			// Special case NUL chrin.
	cmpne	pchr.b, pchr_nul/z, zdata.b, 0	// Matched chrin?
	csel	result, src, xzr, first		// If it is NUL, return null.
#endif
2:	ret

	.p2align 3
L(pagecross):
	mov	vlalign, 0
	decb	vlalign
	orn	tmp, src, vlalign		// Find end of VL aligned src.
	whilels	psrc.b, src, tmp		// Mask off elements.
	ld1b	{zdata.b}, psrc/z, [src]
	match	pchr_nul.b, psrc/z, zdata.b, zchr_nul.b
	b.any	L(firstmatch)
	and	src, src, vlalign		// Align src to VL.
	b	L(loop2)

END (FUNC)
