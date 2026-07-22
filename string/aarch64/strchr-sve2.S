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

#define srcin		x0		// const char* src.
#define chrin		w1		// int chr.
#define result		x0		// Return.

#define	vlalign		x2		// Alignment mask.
#define	src		x3		// Current data pointer.

#define zdata		z0		// Data.
#define zchr_nul	z1		// chr and null data for search.

#define pall		p0		// All active predicate.
#define pchr_nul	p1		// chr and null search result.
#define pchr		p2		// chr search result.
#define psrc		p3		// Mask of chars before srcin.
#define pfirst		p4		// First found.

ENTRY (FUNC)
	mov	vlalign, -1		// Create alignment mask based on VL.
	incb	vlalign
	and	chrin, chrin, 0xff	// Set zeros after first byte.
	dup	zchr_nul.h, chrin	// Initialize chr and null for search.
	bic	src, srcin, vlalign	// Align src to VL.
	ptrue	pall.b			// Initialize all active.

	ld1b	{zdata.b}, pall/z, [src]	// Read next chunk.
	match	pchr_nul.b, pall/z, zdata.b, zchr_nul.b	// Find chr or null.
	b.none	L(loop2)

	brkb	pfirst.b, pall/z, pchr_nul.b	// Find first element.
	incp	src, pfirst.b		// Increment result by element index.
	cmp	src, srcin		// Is result before srcin?
	b.lo	L(first_chunk)		// If yes, special case first chunk.

#if !defined (BUILD_STRCHRNUL)
	cbz	chrin, L(match0)		// Special case NUL char.
	cmpne	pchr.b, pchr_nul/z, zdata.b, 0	// Matched search char or NUL?
	csel	result, src, xzr, first		// If it is NUL, return null.
	ret

L(match0):
	mov	result, src
	ret
#endif

	.p2align 4
L(first_chunk):
	bic	src, srcin, vlalign
	whilelo psrc.b, src, srcin		// Mask for chars before src.
	bics	pchr_nul.b, pall/z, pchr_nul.b, psrc.b // Remove early matches.
	b.none	L(loop2)

	brkb	pfirst.b, pall/z, pchr_nul.b	// Find first element.
	incp	src, pfirst.b			// Increment by element index.
#if !defined (BUILD_STRCHRNUL)
	cbz	chrin, L(match0)		// Special case NUL char.
	cmpne	pchr.b, pchr_nul/z, zdata.b, 0	// Matched search char or NUL?
	csel	result, src, xzr, first		// If it is NUL, return null.
	ret
#else
	mov	result, src
	ret
#endif

	.p2align 4
L(loop):
	ld1b	{zdata.b}, pall/z, [src]	// Read next chunk.
	match	pchr_nul.b, pall/z, zdata.b, zchr_nul.b	// Find chr or null.
	b.any	L(loop_end)	// If chr or null are found, move to end.
L(loop2):
	ld1b	{zdata.b}, pall/z, [src, 1, mul vl]	// Read next chunk.
	incb	src, all, mul 2				// Increment by 2xVL.
	match	pchr_nul.b, pall/z, zdata.b, zchr_nul.b	// Find chr or null.
	b.none	L(loop)		// If chr or null are not found, repeat loop.

	decb	src				// Decrement by VL.

L(loop_end):
	brkb	pfirst.b, pall/z, pchr_nul.b	// Find first element.
	incp	src, pfirst.b			// Increment by element index.
#if !defined (BUILD_STRCHRNUL)
	cbz	chrin, L(match0)		// Special case NUL char.
	cmpne	pchr.b, pchr_nul/z, zdata.b, 0	// Matched search char or NUL?
	csel	result, src, xzr, first		// If it is NUL, return null.
	ret
#else
	mov	result, src
	ret
#endif

END (FUNC)
