#include "nine.h"
#include "unix/atomic-ops.h"


/* 
 * libuv portable operating system support
 *
 */

// signals
uv_signal_t sig_pipe;
uv_signal_t sig_user1;
uv_signal_t sig_term;
uv_signal_t sig_ill;
uv_signal_t sig_fpe;
uv_signal_t sig_bus;
uv_signal_t sig_segv;
uv_signal_t sig_int;

// request dispatcher baton
uv_prepare_t dispatch_prep;
uv_idle_t idle_watcher;

void cleanexit(uv_signal_t *, int);

// default console
extern uv_tty_t tty;
extern uv_async_t ev_conschar;
extern uv_loop_t* kbdloop;

// CLI options
extern int dflag;   // true if running in detached state
extern int sflag;   // true if signals set for kernel debug

static void
sysfault(char *what, void *addr)
{
	char buf[64];

	snprint(buf, sizeof(buf), "sys: %s%#p", what, addr);
	/* disfault(nil, buf); */
}

static void
trapILL(uv_signal_t* handle, int signo /*, siginfo_t *si, void *a*/)
{
	USED(signo);
	//USED(a);
	//sysfault("illegal instruction pc=", si->si_addr);
    panic("illegal instruction\n");
}

static int
isnilref(siginfo_t *si)
{
	return si != 0 && (si->si_addr == (void*)~(uintptr_t)0 || (uintptr_t)si->si_addr < 512);
}

static void
trapmemref(uv_signal_t* handle, int signo /*, siginfo_t *si, void *a */)
{
	//USED(a);	/* ucontext_t*, could fetch pc in machine-dependent way */
	//if(isnilref(si)) {
		// disfault(nil, exNilref);
        //sysfault("nil signal information reference");
    //}
	//else
    if(signo == SIGBUS) {
		//sysfault("bad address addr=", si->si_addr);	/* eg, misaligned */
        panic("bad address");
    }
	else {
		//sysfault("segmentation violation addr=", si->si_addr);
        panic("segmentation violation");
    }
}


/* FIX: VM dependent.  Lua has it's own trap handler for this.
 * It probably should not be actively enabled in the signal system.
 * No-op'd for now...
 */
/*static void
trapFPE(int signo, siginfo_t *si, void *a)
{
	char buf[64];

	USED(signo);
	USED(a);
	snprint(buf, sizeof(buf), "sys: fp: exception status=%.4lux pc=%#p", getfsr(), si->si_addr);
	disfault(nil, buf);
}
*/
void
trapUSR1(uv_signal_t* handle, int signo)
{
    USED(signo);
    
    if(up->ptype != Vm_proc)      /* Used to unblock pending I/O */
        return;
    /* if(up->intwait == 0) */        /* Not posted so its a sync error */
    /*    disfault(nil, Eintr); */	/* Should never happen */
    
    //up->intwait = 0;		/* Clear it so the proc can continue */
}

/* from geoff collyer's port */
void
printILL(uv_signal_t* handle, int sig /*, siginfo_t *si, void *v*/)
{
	USED(sig);
	//USED(v);
	//panic("illegal instruction with code=%d at address=%p, opcode=%#x\n",
	//	si->si_code, si->si_addr, *(uchar*)si->si_addr);
	panic("illegal instruction in VM\n");
}

// just dummy code to ignore signal
void 
ignore(uv_signal_t *handle, int signo)
{
    return;
}

// these hook the libuv equivalents and are sent to the primary loop by default
void
setsigs(void)
{        
    /* We intercept signals only for the default loop */
	uv_signal_init(uv_default_loop(), &sig_pipe);
    uv_signal_start(&sig_pipe, ignore, SIGPIPE);
	//uv_signal_init(uv_default_loop(), &sig_term);
    //uv_signal_start(&sig_term, cleanexit, SIGTERM);

    uv_signal_init(uv_default_loop(), &sig_user1);
    uv_signal_start(&sig_user1, trapUSR1, SIGUSR1);


    // normal inferno exception processing?
	if(sflag == 0) {
        // yes, so...
        // trap illegal instructions
        uv_signal_init(uv_default_loop(), &sig_ill);
        uv_signal_start(&sig_ill, trapILL, SIGILL);
        // don't trap floating point exceptions (let luajit do that)
        //uv_signal_init(uv_default_loop(), &sig_fpe);
        //uv_signal_start(&sig_fpe, trapFPE, SIGFPE);
        // trap bus and memory exceptions
        uv_signal_init(uv_default_loop(), &sig_bus);
        uv_signal_start(&sig_bus, trapmemref, SIGBUS);
        uv_signal_init(uv_default_loop(), &sig_segv);
        uv_signal_start(&sig_segv, trapmemref, SIGSEGV);
        // trap int kills and exit (if possible)
        uv_signal_init(uv_default_loop(), &sig_int);
        uv_signal_start(&sig_int, cleanexit, SIGINT);
	} else {
        // else we instrument to debug inferno VM itself
        uv_signal_init(uv_default_loop(), &sig_ill);
        uv_signal_start(&sig_ill, printILL, SIGILL);
	}
}

// initialize req and event watchers
void
setwatchers(void)
{
   uv_prepare_init(uv_default_loop(),&dispatch_prep);
   uv_prepare_start(&dispatch_prep, dispatch);
   uv_idle_init(uv_default_loop(),&idle_watcher);
   uv_idle_stop(&idle_watcher);
}

void
stopsigs(void)
{        
    /* Shutdown default handlers */
    uv_signal_stop(&sig_pipe);
    //uv_signal_stop(&sig_term);
    uv_signal_stop(&sig_user1);

    /* normal handlers */
	if(sflag == 0) {
        uv_signal_stop(&sig_ill);
        // don't trap floating point exceptions (let luajit do that)
        //uv_signal_stop(&sig_fpe);
        // trap bus and memory exceptions
        uv_signal_stop(&sig_bus);
        uv_signal_stop(&sig_segv);
        // trap int kills and exit (if possible)
        uv_signal_stop(&sig_int);
	} else {
        // else inferno was running in a debug env
        uv_signal_stop(&sig_ill);
	}
    
}

void
drain_events(hproc_t* p)
{
    /* flush any remaining events in the default loop */
    uv_run(p->loop, UV_RUN_NOWAIT);
}

void
termset(void)
{
    /* init stdin and we intend to read it (1) */
    kbdloop = uv_loop_new();
    uv_tty_init(kbdloop, &tty, STDIN_FILENO, 1);

    /* set mode to raw: one char at a time, no editing */
    uv_tty_set_mode(&tty, 1);
}


void
termrestore(void)
{
    uv_tty_reset_mode();
}


void
cleanexit(uv_signal_t *handle, int x)
{
	USED(x);

/*	if(up->intwait) {
		up->intwait = 0;
		return;
	} */

	if(dflag == 0)
		termrestore();

	exit(0);
}

int
os_canspinlock(Lock* l)
{
#ifdef _MSC_VER
   char volatile *v = (char volatile*)&l->val;
   return uv__atomic_exchange_set(v)); // val should be a 'char volatile*'
#else
   return __sync_bool_compare_and_swap(&l->val, 0, 1);
#endif
}

void
os_spinlock(Lock* l)
{    
	int i;

	if(os_canspinlock(l))
		return;
	for(i=0; i<100; i++){
		if(os_canspinlock(l))
			return;
		osyield();
	}
	for(i=1;; i++){
		if(os_canspinlock(l))
			return;
		osmillisleep(i*10);
		if(i > 100){
			osyield();
			i = 1;
		}
	}
}


void
os_spinunlock(Lock *l)
{
    int volatile* p = &l->val;
    asm volatile ("");   // memory barrier
    *p=0;
}

