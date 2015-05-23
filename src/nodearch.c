/*
 * cpu-specific architecture information, part of libarch
 *
 * cpu type, arch, sizeof words and various structures like jump bufs etc
 *
 * this module and nodetopo comprise 'libarch'
 */
#include "dat.h"
//#include "emu.h"
 
//extern char*   hosttype;
//extern char*   cputype;

char *cputype = "amd-64";
char *hosttype = "MacOSX";

char *hostcpu() {
    return cputype;
}
    
char *hostos() {
    return hosttype;
}

/* the machine architecture word size in bytes, usually 4 or 8 */
int wordsize() {
    return sizeof(long);
}


/* number of 32-bit words (ints) in the os machine state */
int jumpsize() {
    return sizeof(osjmpbuf) >> 2;
}
