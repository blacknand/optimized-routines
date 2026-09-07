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

/*
	The program is divided into several sections to deal with different sizes
	of memory that have been requested for filling in:
	| Size 			|	 Strategy 						| Reason 											 |
	|---------------|-----------------------------------|----------------------------------------------------|
	| 0–15 			| One predicated SVE store 			| Writes exactly the requested lanes without overrun |
	| 16–64 		| Four 16-byte stores 				| Fixed, branch-free sequence; stores may overlap    |
	| 65–128 		| First 64 bytes plus last 64 bytes | Those regions meet or overlap 				     |
	| 129–255 		| 64-byte NEON loop 				| First and last 64 bytes no longer cover everything |
	| ≥256, zero 	| Aligned `DC ZVA` loop				| Setup cost is spread across enough 64-byte blocks  |
	| ≥256, nonzero | NEON loop 						| `DC ZVA` can only write zeros 					 |
 */

ENTRY (__memset_aarch64_sve2)
	/* TODO: think about the correct load given the size of the vector + number of vectors
	   for whatever core this is */

	/* TODO: Investigate if there is a better way to branch? */
	cbz count, null_count

	dup v0.16B, valw		
	add dstend, destin, count
	/* TODO: Investigate how to check if the alignemnt is near 4096 with a count of < 16 */
	cmp count, 16
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
	/* Manually avoid a page cross by splitting the store into two seperate operations
		on both sides of the page boundary. If there is no page cross then the stores
		are performed overlapping. */

	/* Note: this does not specifically target page boundaries, so is it faster both
		at page boundaries and not at page boundaries? Do benchmarking to find out */

	/* Note: on Neoverse V2/Phoenix, SVE is only 128 bits (16 bytes), so this case occurs 
		only when a vector begins within the final 15 bytes of a page. */

	/* x3 (dest) will be reused because it only stores successive calculations. */
	bic dest, destin, 15				/* Align down destin to a 16-byte address */
	add dest, dest, 16
	cmp dest, destend
	/* dest is the split point: if the requested region crosses the next 16-byte boundary,
		dest is that boundary. If it does not cross, then dest is simply the end. */
	csel dest, dest, destend, lo		/* dest = (dest >= destin) ? dest : destin */

	/* Generate the first predicate from the original source up to the split, and then
		generate the second predicate from the split until the destination. */
	whilelo p0.b, destin, dest
	whilelo p1.b, dest, dstend

	/* Use same vector registers, different predicates and different base addresses */
	st1b	z0.b, p0, [destin]		
	st1b	z0.b, p1, [dest]		
	ret

END (__memset_aarch64_sve2)
