#include	<sys/types.h>
#include	<time.h>
#include	<termios.h>
#include	<signal.h>
#include 	<pwd.h>
#include	<sched.h>
#include	<sys/resource.h>
#include	<sys/wait.h>
#include	<sys/time.h>

#include	<stdint.h>

#include "nine.h"

#include <semaphore.h>

#include	<raise.h>

/* glibc 2.3.3-NTPL messes up getpid() by trying to cache the result, so we'll do it ourselves */
#include	<sys/syscall.h>
#define	getpid()	syscall(SYS_getpid)

enum
{
	DELETE	= 0x7f,
};

char *hosttype = "Linux";
char *cputype = OBJTYPE;

extern int dflag;

int	gidnobody = -1;
int	uidnobody = -1;

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
	error("reboot failure");
}

/*
 * Return an abitrary millisecond clock time
 */
long
osmillisec(void)
{
	static long sec0 = 0, usec0;
	struct timeval t;

	if(gettimeofday(&t,(struct timezone*)0)<0)
		return 0;

	if(sec0 == 0) {
		sec0 = t.tv_sec;
		usec0 = t.tv_usec;
	}
	return (t.tv_sec-sec0)*1000+(t.tv_usec-usec0+500)/1000;
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
	struct  timespec time;

	time.tv_sec = milsec/1000;
	time.tv_nsec= (milsec%1000)*1000000;
	nanosleep(&time, NULL);
	return 0;
}

int
limbosleep(ulong milsec)
{
	return osmillisleep(milsec);
}
