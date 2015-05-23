#include "nine.h"
#include	"interp.h"

/* kernel process support functions:
 *
 * note: the list of kernel procs are tracked in the "procs" list while the list
 *       of interpreter procs are stored in the "progs" list.
 *
 * hosted virtual proc functions are located in vm.c
 *
 */

static int gpid = 0;                // global kernel process pid list

/* make a new bare kernel proc */
kproc_t*
new_kproc(void)
{
	kproc_t* p;

	p = malloc(sizeof(kproc_t));
	if(p == nil)
		return nil;

	p->killed = 0;
    p->env = &p->defenv;
    
	kstrdup(&p->env->user, "*nouser");
	p->env->errstr = p->env->errbuf0;
	p->env->syserrstr = p->env->errbuf1;
    
    p->pid = gpid++;
    
    p->ptype = Kern_proc;
    
    /* by default this proc is self-hosting */
    p->hproc = (hproc_t*)p;
    
	return p;
}

void async_debug(uv_async_t *handle) {
    fprintf(stderr, "--------------->>>loop woke up<<<----------------------\n");
}
/* make a new kernel proc that hosts user vprocs on event 'loop' */
hproc_t*
new_hproc(uv_loop_t* loop)
{
	hproc_t* p;

	p = malloc(sizeof(hproc_t));
	if(p == nil)
		return nil;

	p->killed = 0;
    p->env = &p->defenv;

	kstrdup(&p->env->user, "*nouser");
	p->env->errstr = p->env->errbuf0;
	p->env->syserrstr = p->env->errbuf1;
    
    p->pid = gpid++;
    
    p->ptype = Host_proc;
    
    /* by default this kproc is self hosting */
    p->hproc = p;
    
    /* initialize interpreter instance fields */
    p->pidnum = 0;
    p->isched.head = p->isched.tail = nil;
    
    /* initialize it's request/reply queues */
    QUEUE_INIT(&p->reqq);
    QUEUE_INIT(&p->repq);

    /* initialize it's event loop and wake signal */
    p->loop = loop;
    uv_async_init(p->loop, &p->ev_wake, async_debug);

	return p;
}

/*
 * sleep and wakeup implement a kind of condition variable semantic for process
 * synchronization.  these are used heavily in the device drivers and qio subsystem.
 * while we could re-implement them by artificially grafting them to the libuv 
 * evented I/O subsystem that would be redundant.  probably easier to simply 
 * change the request flow in the drivers to match the event I/O model and let
 * the callbacks wakeup and reschedule the fibers etc.  until then the lower-level
 * enabling calls on these like osblock/osready etc are no-ops.
 */

void
Sleep(Rendez *r, int (*f)(void*), void *arg)
{
    kproc_t* p = (kproc_t*)up;
    
	lock(&p->rlock);
	lock(&r->l);

	// if interrupted or more work, don't sleep
	if(p->killed || f(arg)) {
		unlock(&r->l);
	}else{
        //print("sleeping on %p\n",r);
		if(r->p != nil)
			panic("double sleep pc=0x%lux %s[%lud] %s[%lud] r=0x%lux\n", getcallerpc(&r), r->p->text, r->p->pid, up->text, up->pid, r);

		r->p = p;
		unlock(&r->l);
		p->swipend = 0;
		p->r = r;	// for swiproc 
		unlock(&p->rlock);

        //print("sleeping on %p and blocking\n", r); 
		osblock();

		lock(&p->rlock);
		p->r = nil;
	}

	if(p->killed || p->swipend) {
        //print("sleeping on %p and killed\n", r);
		p->killed = 0;
		p->swipend = 0;
		unlock(&p->rlock);
		error(Eintr);
	}
	unlock(&p->rlock);
}

int
Wakeup(Rendez *r)
{
	kproc_t *p;

	lock(&r->l);
	p = r->p;
	if(p != nil) {
		r->p = nil;
		osready(p);
	}
	unlock(&r->l);
	return p != nil;
}


/* probably easier ways to do swiproc also, but we'll leave as is
 * for now.  swiproc is used by dis.c and exportfs.c for proc synchro.
 * otherwise swiproc is a "software interrupt" mechanism using the 
 * already established process synch mechanisms.  we'll probably have
 * to replace it with an async_send in libuv.
 */
void
swiproc(kproc_t *p, int interp)
{
	Rendez *r;
	
    print("swiproc: %p, interp=%d\n",p,interp);
	if(p == nil)
		return;

	
	//  Pull out of emu Sleep
	
	lock(&p->rlock);
	if(!interp)
		p->killed = 1;
	r = p->r;
    //print("swiproc: %p is killed is %d on rendez %p\n",p,p->killed, r);
	if(r != nil) {
		lock(&r->l);
		if(r->p == p) {
            //print("swiproc: setting software interrupt pending\n");
			p->swipend = 1;
			r->p = nil;
			osready(p);
		}
		unlock(&r->l);
		unlock(&p->rlock);
		return;
	}
	unlock(&p->rlock);

	
	// Exit any executing Host OS command
	
	lock(&p->sysio);
	if(p->syscall && p->intwait == 0) {
		p->swipend = 1;
		p->intwait = 1;
		unlock(&p->sysio);
		oshostintr(p);
		return;	
	}
	unlock(&p->sysio);
}

void
notkilled(void)
{
    kproc_t* kp = (kproc_t*)up;
	lock(&kp->rlock);
	kp->killed = 0;
	unlock(&kp->rlock);
}

/* osenter is called just before making a call to the host operating system.
 * osleave is called just after making a call to the host operating system.
 * these are both handled asynchronously by the libuv worker thread, so all
 * we do is flag the state and use it if we need to.
 * 
 * note: in both of these the syscall is flagged in the current proc, not
 * the underlying kernel proc since it can't afford to stop
 */
void
osenter(void)
{
	up->syscall = 1;
}

void
osleave(void)
{
    up->syscall = 0;
}
