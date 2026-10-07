#include <stdio.h>
#include <string.h>

/*
x0 = destination pointer
w1 = fill value
x2 = length
x0 on return = returned destination pointer
*/

extern void* __memset_aarch64_sve(void* s, int c, size_t n);

int main(void)
{
	unsigned char* buffer[16];
	__memset_aarch64_sve(buffer, 0, 256);
	return 0;
}