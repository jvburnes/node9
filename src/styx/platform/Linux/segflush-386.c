#include <sys/types.h>
#include <sys/syscall.h>

#include "nine.h"

int
segflush(void *a, ulong n)
{
	USED(a); USED(n);
	return 0;
}
