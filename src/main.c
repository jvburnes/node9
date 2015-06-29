/* basic node9, stdio, uv and ixp imports */

#include <stdlib.h>
#include "nine.h"
#include "version.h"

/* lua stuff */

#include <lua.h>                                /* Always include this when calling Lua */
#include <lauxlib.h>                            /* Always include this when calling Lua */
#include <lualib.h>                             /* Always include this when calling Lua */

#include "kerndate.h"
int tracelvl = TRACE_INFO;
char* tstrings[] = { "INFO", "WARN", "ERROR", "DEBUG" };
int   tlevels[] = {TRACE_INFO, TRACE_WARN, TRACE_ERROR, TRACE_DEBUG };


static  char    *imod = "/os/init/nodeinit.lua";

void luaL_abort9(lua_State *L, char *msg){
	trace(TRACE_INFO, "\nFATAL ERROR:\n  %s: %s\n\n", msg, lua_tostring(L, -1));
	exit(1);
}


        hproc_t*    kern_base;          /* primary kernel process */
        Procs       procs;              /* the process list (kern and shadow) */
        char*       eve;                /* username node9 is running under */
        int         hostuid;            /* numeric uid node9 is running as */
        int         hostgid;            /* numeric gid node9 is running as */
        int         rebootargc = 0;     /* save space for kernel reboot values */
        char**      rebootargv;

extern  char*       hosttype;
extern  char*       cputype;
extern  Bhdr*       ptr;

        int         dflag = 0;          /* true when node9 running detached from cons */
//extern  int         vflag;              /* verbose startup */
        int         node9_running;      /* all procs must exit when this goes true */


/* This is the primary lua init thread.
 * It initializes the luaspace kernel environment and then loads and runs
 * the lua kernel loader
 */
void inituser(void *arg)
{
    lua_State *L;
    int error;
    char *luainit;
    hproc_t* hp = (hproc_t*) up;        // the hosting proc (kernel)
    
    trace(TRACE_INFO, "node9/kernel: starting luaspace ...");
 
    trace(TRACE_INFO, "signals set");
    
    /* create the root virtual process which will become 'init' */
    /*lock(&hp->isched.l);
    hp->rootproc = new_vproc((proc_t*)hp, KPDUPPG | KPDUPFDG | KPDUPENVG);
    unlock(&hp->isched.l); */

    trace(TRACE_DEBUG, "vproc created");
    
    /* create the lua userland */
    L = luaL_newstate();
    luaL_openlibs(L);
    trace(TRACE_DEBUG, "node9/init: lua state initialized");

    if (!(luainit = malloc(strlen(rootdir)+strlen(arg)+1))) {
	trace(TRACE_INFO, "node9/kernel: could not alloc memory for init module");
        luaL_abort9(L, "node9/init: could not alloc init string");
    }
    *luainit = 0;
    strcat(luainit, rootdir);
    strcat(luainit, arg);

    /* then load the init script */
    if (error = luaL_loadfile(L, luainit)) {
        trace(TRACE_INFO, "node9/loadfile: did not exit cleanly, err = %d",error);
	    luaL_abort9(L, "node9/init: could not load lua scheduler");
    }

    /* instantiate the init function */
    if (error = lua_pcall(L, 0, 0, 0)) {
        trace(TRACE_INFO, "node9/pcall: vm pipeline did not initialize cleanly, err - %d",error);
	    luaL_abort9(L, "node9/init: setup failed");
    }

    /* make sure the error stack is at baseline */
    assert(up->nerr == 0);
    
    /* and start the init script with fs root */
    lua_getglobal(L, "init");                 /* bootstrap start funtion */
    lua_pushstring(L, rootdir);                  /* fs root is the basis for all else */
    
    if (error = lua_pcall(L, 1, 0, 0)) {
        trace(TRACE_INFO, "node9: pcall: did not exit cleanly, err = %d",error);
	    luaL_abort9(L, "node9/init: could not start lua scheduler");
    }

    /* Clean up and free the Lua state variables, coroutines, objects -- forces last GCs */
    lua_close(L);

    trace(TRACE_WARN, "node9/inituser: (host thread) / lua start process exited with err %d",error);
    /* were done, so stop listening to global signals */
    stopsigs();
    
    free(luainit); 

    trace(TRACE_WARN, "node9/inituser: (host thread) / lua start process exited with err %d",error);
    /* were done, so stop listening to global signals */
    stopsigs();
    
    /* this drains any remaining event callbacks, but will leak memory -- FIX */
    //drain_events(hp);
    
    // this releases the root vproc (init)
    // (first clear the error buffer)
    //hp->rootproc->env->errstr = "";
    
    //lock(&hp->isched.l);
    //progexit(hp->rootproc);
    //unlock(&hp->isched.l);
    
    /* tell any kernel slaves to exit */
    node9_running = false;
    
}


/*
 * --- node9 kernel ---
 */

/* create an initial namespace for calling kproc
 *
 * 
 */
void
k_namespace()
{

    Osenv* e = up->env;
    int mnum;
    
    if(waserror()) {
        panic("initializing kernel environment");
    }
    
    /* bind the root device */
    trace(TRACE_DEBUG, "node9/kernel: initializing kernel namespace for %p",up);
  	e->pgrp->slash = namec("#/", Atodir, 0, 0);
	cnameclose(e->pgrp->slash->name);
	e->pgrp->slash->name = newcname("/");
	e->pgrp->dot = cclone(e->pgrp->slash);
    
	poperror();

	strcpy(up->text, "main");

    // open node9's standard streams

    trace(TRACE_INFO, "node9/kernel: binding standard streams");

    if(kopen("#c/cons", OREAD) != 0) {                      // STDIN
		trace(TRACE_INFO,"failed to open STDIN on #c/cons");
    }
    
    /* cycle the event loop */
    
	if (kopen("#c/cons", OWRITE) != 1) {                   // STDOUT
		trace(TRACE_INFO,"failed to open STDOUT on #c/cons");
    }
    
    /* cycle the event loop */
    
    if (kopen("#c/cons", OWRITE) != 2) {                   // STDERR
		trace(TRACE_INFO,"failed to open STDERR on #c/cons");
    }

	/* the setid cannot precede the bind of #U */
    /* bind unix-style local file system */
    if (kbind("#U", "/", MAFTER|MCREATE) == -1) {
		trace(TRACE_INFO,"failed to bind fs on /, err = '%s'",up->env->errstr);
    }

    
    trace(TRACE_DEBUG, "node9/kernel: namespace/setting eve to %s",eve);
	setid(eve, 0);

/* we don't use the cut-paste device (snarf) or mouse pointer 
	kbind("#^", "/dev", MBEFORE);
	kbind("#^", "/chan", MBEFORE);
	kbind("#m", "/dev", MBEFORE);
*/

	mnum = kbind("#c", "/dev", MBEFORE);        // console device
    trace(TRACE_DEBUG, "console bound, mount id %d",mnum);
    mnum = kbind("#e", "/env", MREPL|MCREATE);  // environment device
    trace(TRACE_DEBUG, "env dev bound, mount id %d",mnum);
//	kbind("#p", "/prog", MREPL);        // prog control device
	mnum = kbind("#d", "/fd", MREPL);           // file descriptor device
    trace(TRACE_DEBUG, "fd dev bound, mount id %d",mnum);
	kbind("#I", "/net", MAFTER);        // net device (obviously)

}

/* here we save the startup args in case of restart */
static void
savestartup(int argc, char *argv[])
{
        int i;
        
        trace(TRACE_DEBUG, "kernel/savestartup: saving %d startup args", argc);
        rebootargc = argc;
        rebootargv = malloc((argc+1)*sizeof(char*));
        if(rebootargv == nil)
                panic("can't save startup args");
        for(i = 0; i < argc; i++) {
                trace(TRACE_DEBUG, "kernel/savestartup: saving '%s'",argv[i]);
                rebootargv[i] = strdup(argv[i]);
                if(rebootargv[i] == nil)
                        panic("can't save startup args");
        }
        rebootargv[i] = nil;
}

/* environment convenience functions */
void
putenvq(char *name, char *val, int conf)
{
        val = smprint("%q", val);
        ksetenv(name, val, conf);
        free(val);
}

void
putenvqv(char *name, char **v, int n, int conf)
{
        Fmt f;
        int i;
        char *val;

        fmtstrinit(&f);
        for(i=0; i<n; i++)
                fmtprint(&f, "%s%q", i?" ":"", v[i]);
        val = fmtstrflush(&f);
        trace(TRACE_DEBUG, "kernel/putenvqv: storing '%s' into env key '%s'",val,name);
        ksetenv(name, val, conf);
        free(val);
}

/* specialized error handling */

/* set formatted error string as current error in kernel */
void
errorf(char *fmt, ...)
{
	va_list arg;
	char buf[PRINTSIZE];

	va_start(arg, fmt);
	vseprint(buf, buf+sizeof(buf), fmt, arg);
	va_end(arg);
	error(buf);
}

/* set err as current error in kernel */
void
error(char *err)
{
	if(err != up->env->errstr && up->env->errstr != nil)
		kstrcpy(up->env->errstr, err, ERRMAX);
	nexterror(up);
}

/* make the last host error the current plan9 error */
void
oserror()
{
	oserrstr(up->env->errstr, ERRMAX);
	error(up->env->errstr);
}

/* jump to the most recent exception catch and execute recovery */
void
nexterror()
{
	oslongjmp(nil, up->estack[--up->nerr], 1);
}

void
exhausted(char *resource)
{
	char buf[64];
	int n;

	n = snprint(buf, sizeof(buf), "no free %s\n", resource);
	iprint(buf);
	buf[n-1] = 0;
	error(buf);
}

/* return the current process error string */
char*
enverror()
{
	return up->env->errstr;
}

/* display formatted abort message and stop all */
void
panic(char *fmt, ...)
{
	va_list arg;
	char buf[512];

	va_start(arg, fmt);
	vseprint(buf, buf+sizeof(buf), fmt, arg);
	va_end(arg);
	fprint(2, "panic: %s\n", buf);
	if(sflag)
		abort();

	exit(0);
}

int
iprint(char *fmt, ...)
{

	int n;	
	va_list va;
	char buf[1024];

	va_start(va, fmt);
	n = vseprint(buf, buf+sizeof buf, fmt, va) - buf;
	va_end(va);

	write(1, buf, n);
	return 1;
}

void
_assert(char *fmt)
{
	panic("assert failed: %s", fmt);
}

/*
 * mainly for libmp
 */
void
sysfatal(char *fmt, ...)
{
	va_list arg;
	char buf[64];

	va_start(arg, fmt);
	vsnprint(buf, sizeof(buf), fmt, arg);
	va_end(arg);
	error(buf);
}

/* for dynamically loaded modules we do try/catch differently */
/* dyn modules use waserr instead of waserror */
    
void*
waserr()
{
	up->nerr++;
	return up->estack[up->nerr-1];
}

void
poperr()
{
	up->nerr--;
}

/*
 * C main synthesizes initial 'kernel' process which starts
 * node9 'main' process.
 *
 */

typedef struct Pool Pool;

struct Pool
{
	char*	name;
	int	pnum;
	ulong	maxsize;
	int	quanta;
	int	chunk;
	int	monitor;
	ulong	ressize;	/* restricted size */
	ulong	cursize;
	ulong	arenasize;
	ulong	hw;
	Lock	l;
	Bhdr*	root;
	Bhdr*	chain;
	ulong	nalloc;
	ulong	nfree;
	int	nbrk;
	int	lastfree;
	void	(*move)(void*, void*);
};


extern Pool* mainmem;
extern Pool* heapmem;
extern Pool* imagmem;

static void
usage(void)
{
        fprint(2, "Usage: node9 [options...] [file.dis [args...]]\n"
                "\t-c<compile-level>[0-9]\n"
                "\t-d <startupfile>.lua\n"
                "\t-t<tracelevel>[INFO|WARN|ERROR|DEBUG]\n"
                "\t-s  (disable signals)\n"
                "\t-v  (verbose startup)\n"
                "\t-p<poolname>=maxsize\n"
                "\t-r<rootpath>\n");

        exits("usage");
}

static void
tracing(char *str)
{
    int i;
    int v = 0;
    
    for(i=0; i<sizeof(tstrings)/sizeof(char*); i++)
    {
        if (strncmp(str, tstrings[i], strlen(tstrings[i])) == 0) {
            tracelvl = tlevels[i];
            v = 1;
            break;
        }
    }
    if (!v) {usage();}
}

static void
poolopt(char *str)
{
        char *var;
        int n;
        ulong x;

        var = str;
        while(*str && *str != '=')
                str++;
        if(*str != '=' || str[1] == '\0')
                usage();
        *str++ = '\0';
        n = strlen(str);
        x = atoi(str);
        switch(str[n - 1]){
        case 'k':
        case 'K':
                x *= 1024;
                break;
        case 'm':
        case 'M':
                x *= 1024*1024;
                break;
        }
        if(poolsetsize(var, x) == 0)
                usage();
}

static void
option(int argc, char *argv[], void (*badusage)(void))
{
        char *cp;

        ARGBEGIN {
        default:
          badusage();
//        case 'c':               /* pre-compile (save tokenized source code) */
//                cp = EARGF(badusage());
//                if (!isnum(cp))
//                        badusage();
//                cflag = atoi(cp);
//                if(cflag < 0|| cflag > 9)
//                        usage();
//                break;
        case 't':       // trace level
                cp = EARGF(badusage());
                tracing(cp);
                break;
        case 'I':       /* (temporary option) run without cons */
                dflag++;
                break;
        case 'd':               /* run as a daemon */
                dflag++;
                imod = EARGF(badusage());
                break;
        case 's':               /* No trap handling */
                sflag++;
                break;
        case 'p':               /* pool option */
                poolopt(EARGF(badusage()));
                break;
        case 'r':               /* Set inferno root */
                strecpy(rootdir, rootdir+sizeof(rootdir), EARGF(badusage()));
                break;
//        case 'v':
//                vflag = 1;      /* print startup messages */
//                break;
        } ARGEND
}


int main(int argc, char **argv)
{
    hproc_t* p;
    char *wdir;

    /* nothing running yet */
    node9_running = false;
    
    /* bind pool free tracking to mainmem instead of heap */
    ptr = poolchain(mainmem);
    
    printf("node9 %s, build: %d  main (pid=%d)\n", VERSION, KERNDATE, getpid());
    
    /* initialize inferno startup variables (formatted i/o, etc) and save restart values */
    trace(TRACE_DEBUG, "node9/kernel: installing new format types");
    quotefmtinstall();
    trace(TRACE_DEBUG, "node9/kernel: saving startup args");
    savestartup(argc, argv);
    
    option(argc, argv, usage);
    
    /* initialize the channel devices */
    chandevinit();


    /* init node9 host and user settings, init stack and signals */
    host_init();
    
    /* (do any startup option processing here) */

    trace(TRACE_INFO, "node9/kernel: loading");
    /* Now we initialize the base kernel thread and bind it to the event subsystem */
    p = kern_base = kern_baseproc(inituser, imod);
    
    trace(TRACE_INFO, "node9/kernel: initializing namespace");
    /* configure the basic service namespace for the kernel */
    k_namespace();

    /* init the host env vars */
    trace(TRACE_INFO, "node9/kernel: initializing host environment");
    if(cputype != nil) ksetenv("cputype", cputype, 1);
    putenvqv("emuargs", rebootargv, rebootargc, 1);
    putenvq("emuroot", rootdir, 1);
    ksetenv("emuargs", "./node9", 1);
    ksetenv("emuroot", rootdir, 1);
    ksetenv("emuhost", hosttype, 1);
    wdir = malloc(1024);
    if(wdir != nil){
            if(getwd(wdir, 1024) != nil)
                    putenvq("emuwdir", wdir, 1);
            free(wdir);
    }


    /* start the userspace 'init' module */
    node9_running = true;

    /* trampoline up to the init kernel process
     * this runs the base proc in the primary thread
     * so we don't have to wait for it to exit
     */
    trace(TRACE_INFO, "node9/kernel: accepting requests");
    
    /* start the kernel */
    tramp(p);

    /* kernel reaches here when it's down.  everything is stopped
     * so clean up what remains and restore the environment 
     */
    trace(TRACE_DEBUG, "node9/kernel: cleanup");

    restore();
    trace(TRACE_INFO, "node9/kernel: halted");
    
    return 0;
}

