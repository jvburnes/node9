/*
 * Loosely based on FreeBSD/os.c and Solaris/os.c
 * Copyright © 1998, 1999 Lucent Technologies Inc.  All rights reserved.
 * Revisions Copyright © 1999, 2000 Vita Nuova Limited.  All rights reserved.
 * Revisions Copyright © 2002, 2003 Corpus Callosum Corporation.  All rights reserved.
 */

#include "nine.h"
#include <raise.h>

#undef _POSIX_C_SOURCE 
#undef getwd

#include	<unistd.h>
#include	<time.h>
#include	<signal.h>
#include	<pwd.h>
#include	<sys/resource.h>
#include	<sys/time.h>

#include 	<sys/socket.h>
#include	<sched.h>
#include	<errno.h>
#include    <sys/ucontext.h>

#include <sys/types.h>
#include <sys/stat.h>

#include <mach/mach_init.h>
#include <mach/task.h>
#include <mach/vm_map.h>

#if defined(__ppc__)
#include <architecture/ppc/cframe.h>
#endif

#include <libkern/OSAtomic.h>

enum
{
    DELETE = 0x7F
};

char *hosttype = "MacOSX";
char *cputype = OBJTYPE;

extern int dflag;

int
segflush(void *va, ulong len)
{
	kern_return_t   err;
	vm_machine_attribute_val_t value = MATTR_VAL_ICACHE_FLUSH;

	err = vm_machine_attribute( (vm_map_t)mach_task_self(),
		(vm_address_t)va,
		(vm_size_t)len,
		MATTR_CACHE,
		&value);
	if(err != KERN_SUCCESS)
		print("segflush: failure (%d) address %lud\n", err, va);
	return (int)err;
}

void
oslongjmp(void *regs, osjmpbuf env, int val)
{
	USED(regs);
	siglongjmp(env, val);
}



void
osreboot(char *file, char **argv)
{
	if(dflag == 0)
		termrestore();
	execvp(file, argv);
	panic("reboot failure");
}



int gidnobody= -1, uidnobody= -1;

void
getnobody()
{
	struct passwd *pwd;

	if((pwd = getpwnam("nobody"))) {
		uidnobody = pwd->pw_uid;
		gidnobody = pwd->pw_gid;
	}
}

void 
host_init()
{
    char sys[64];
    struct passwd *pw;

    trace(TRACE_DEBUG, "node9/kernel: becoming host os process leader ");

    /* init system stack */
    setsid();

    trace(TRACE_DEBUG, "node9/kernel: collecting system info");

    /* setup base system personality and user details */
	gethostname(sys, sizeof(sys));
	kstrdup(&ossysname, sys);
	getnobody();

    /* initialize signals and eventing system */

    /* if not a daemon, initialize the terminal */

    if(dflag == 0) {
    	trace(TRACE_INFO, "node9/kernel: initializing terminal");
        termset();
    }

    trace(TRACE_DEBUG, "node9/kernel: initializing signals");
    setsigs();

    trace(TRACE_DEBUG, "node9/kernel: initializing event and req watchers");
    setwatchers();
 
    trace(TRACE_DEBUG, "node9/kernel: establishing host username, uid, pid");

    pw = getpwuid(getuid());
    if(pw != nil)
            kstrdup(&eve, pw->pw_name);
    else
            print("cannot getpwuid\n");

    /* and record the current host user uid/gid */
    hostuid = getuid();
    hostgid = getgid();
    
}

void
restore()
{
    
    /* restore the terminal */
    if(dflag == 0) {
    	trace(TRACE_INFO, "node9/kernel: restoring terminal");
        termrestore();
    } 
}


/*
 * Return an abitrary millisecond clock time
 */
long
osmillisec(void)
{
	static long	sec0 = 0, usec0;
	struct timeval t;

	if(gettimeofday(&t, NULL) < 0)
		return(0);
	if(sec0 == 0) {
		sec0 = t.tv_sec;
		usec0 = t.tv_usec;
	}
	return((t.tv_sec - sec0) * 1000 + (t.tv_usec - usec0 + 500) / 1000);
}

/*
 * Return the time since the epoch in nanoseconds and microseconds
 * The epoch is defined at 1 Jan 1970
 */
vlong
osnsec(void)
{
	struct timeval t;

	gettimeofday(&t, nil);
	return (vlong)t.tv_sec*1000000000L + t.tv_usec*1000;
}

vlong
osusectime(void)
{
	struct timeval t;

	gettimeofday(&t, nil);
	return (vlong)t.tv_sec * 1000000 + t.tv_usec;
}

int
osmillisleep(ulong milsec)
{
	struct timespec time;
    
	time.tv_sec = milsec / 1000;
	time.tv_nsec = (milsec % 1000) * 1000000;
	nanosleep(&time, nil);
	return 0;
}

void
ospause(void)
{
	for(;;)
		pause();
}

__typeof__(sbrk(0))
sbrk(int size)
{
	void *brk;
	kern_return_t   err;
    
	err = vm_allocate( (vm_map_t) mach_task_self(),
                       (vm_address_t *)&brk,
                       size,
                       VM_FLAGS_ANYWHERE);
	if(err != KERN_SUCCESS)
		brk = (void*)-1;
	return brk;
}

