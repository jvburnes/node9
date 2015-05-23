#include "nine.h"
#include "kerndate.h"

#include "emu.root.h"

ulong ndevs = 29;

extern Dev rootdevtab;
extern Dev envdevtab;

extern Dev consdevtab;
extern Dev mntdevtab;
extern Dev pipedevtab;
/*extern Dev progdevtab;
extern Dev profdevtab;
extern Dev srvdevtab;
*/
extern Dev dupdevtab;
extern Dev ssldevtab;
/*extern Dev capdevtab;
*/
extern Dev fsdevtab;
/*
extern Dev cmddevtab;
extern Dev indirdevtab;
*/
extern Dev ipdevtab;
/*
extern Dev memdevtab;
*/
Dev* devtab[]={
	&rootdevtab,
	&envdevtab,
	&consdevtab,
	&mntdevtab,
	&pipedevtab,
/*	&progdevtab,
	&profdevtab,
	&srvdevtab,
*/
	&dupdevtab,	
    &ssldevtab,
/*	&capdevtab,
*/
	&fsdevtab,
/*
	&cmddevtab,
	&indirdevtab,
*/
	&ipdevtab,
/*
	&memdevtab,
*/
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil,
	nil  
};

void links(void){
}

/*
extern void sysmodinit(void);
extern void mathmodinit(void);
extern void srvmodinit(void);
extern void keyringmodinit(void);
extern void loadermodinit(void);
*/

/*
void modinit(void){
	sysmodinit();
	mathmodinit();
	srvmodinit();
	keyringmodinit();
	loadermodinit();

}
*/
ulong kerndate = KERNDATE;

/* The emulator memory block pointer.   This is just needed on a per-pool basis.
 * and since we don't use the heap pool (yet), we need to initialize it for mainmem.
 */
Bhdr* ptr;

