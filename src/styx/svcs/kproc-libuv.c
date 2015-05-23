#include "nine.h"

#undef _POSIX_C_SOURCE 
#undef getwd

#include	<unistd.h>
#include	<signal.h>
#include	<limits.h>
#include	<errno.h>
#include	<semaphore.h>


uv_key_t  prdakey;

extern int dflag;

/* kproc exit */
void
pexit(char *msg, int t)
{
	Osenv *e;
	kproc_t* p;
	Osdep *os;

	USED(t);

    /* get our process context and remove ourselves from proc list
     */
    trace(TRACE_DEBUG, "kernel/pexit: process shutdown");
    
	p = (kproc_t*)up;

	lock(&procs.l);
	if(p->prev)
		p->prev->next = p->next;
	else
		procs.head = p->next;

	if(p->next)
		p->next->prev = p->prev;
	else
		procs.tail = p->prev;
	unlock(&procs.l);

	if(0)
		print("pexit: %s: %s\n", p->text, msg);

    trace(TRACE_DEBUG, "kernel/pexit: releasing resources"); 
    
    /* release name,fid and env groups */
	e = p->env;
	if(e != nil) {
    trace(TRACE_DEBUG, "kernel/pexit: closing fgrp"); 
		closefgrp(e->fgrp);
    trace(TRACE_DEBUG, "kernel/pexit: closing pgrp"); 
		closepgrp(e->pgrp);
    trace(TRACE_DEBUG, "kernel/pexit: closing egrp"); 
		closeegrp(e->egrp);
    trace(TRACE_DEBUG, "kernel/pexit: closing signatures"); 
		closesigs(e->sigs);
    trace(TRACE_DEBUG, "kernel/pexit: freeing user");
		free(e->user);
	}
	
    /* release os dependencies */
	os = p->os;
    if(os != nil){
        trace(TRACE_DEBUG, "kernel/pexit: deleting semaphore"); 
		uv_sem_destroy(&os->sem);
        trace(TRACE_DEBUG, "kernel/pexit: freeing os dependencies"); 
		free(os);
	}
       
    /* release the process itself */
    trace(TRACE_DEBUG, "kernel/pexit: freeing process"); 
	free(p);
}

/*
 * tramp is the first thread component that runs as the new kernel process.  it initializes
 * bare kernel procs and host kernel procs, binds them to the new thread and runs their
 * start up function.
 */
void
tramp(void *arg)
{
	kproc_t* p;
	Osdep *os;
    
    /* get the process */
	p = (kproc_t*)arg;
	os = p->os;
	os->self = uv_thread_self();
     
    /* make it the current proc in TLS */
	uv_key_set(&prdakey, p);    

    /* start the process */
    trace(TRACE_DEBUG, "kernel/tramp: starting kernel process '%s'",p->text);
	p->func(p->arg);
    trace(TRACE_DEBUG, "kernel/tramp: kernel process '%s' exited, releasing resources",p->text);
    
    /* the process terminated, so clean up */
	pexit("{Tramp}", 0);
    
}

uv_idle_t idle_watcher;
void debug_idle(uv_idle_t* handle) {
    printf("========== idling ===========\n");
}

uv_prepare_t prepare_watcher;
void debug_prepare(uv_prepare_t* handle) {
    printf("========== preparing ===========\n");
}

uv_prepare_t poll_watcher;
void debug_poll(uv_poll_t* handle) {
    printf("========== polling ===========\n");
}

uv_check_t check_watcher;
void debug_check(uv_check_t* handle) {
    printf("========== checking ===========\n\n\n\n");
}




hproc_t*
kern_baseproc(void (*start_func)(void *arg), char *start_module)
{
    hproc_t *p;
    Osdep *os;
    Osenv *e;

    /* create a kernel hosting proc */
    p = new_hproc(uv_default_loop());

    /* bind the base proc to the startup thread */
    baseinit(p);
    
    /* append it to the proc list */
    procs.head = p;
    p->prev = nil;
	procs.tail = p;

    /* setup the skeleton process environment */
    e = p->env;
    e->pgrp = newpgrp();
    e->fgrp = newfgrp(nil);
    e->egrp = newegrp();
    e->errstr = e->errbuf0;
    e->syserrstr = e->errbuf1;
    //e->user = strdup("node9");
    e->uid = hostuid;
    e->gid = hostgid;


    /* allocate the os dependency structure */
    os = malloc(sizeof(*os));
	if(os == nil) {
		panic("host_proc: no memory");
    }
    p->os = os;

    os->self = uv_thread_self();  // just the handle for primary thread
    os->thread = nil;             // because its the process thread itself

	uv_sem_init(&os->sem, 0);
    
    /* insert the startup function and module */
    p->func = start_func;
    p->arg = start_module;
    
    /* debug watchers */
    //uv_idle_init(p->loop, &idle_watcher);
    //uv_idle_start(&idle_watcher, debug_idle);
    //uv_prepare_init(p->loop, &prepare_watcher);
    //uv_prepare_start(&prepare_watcher, debug_prepare);
    //uv_poll_init(p->loop, &poll_watcher,0);
    //uv_poll_start(&poll_watcher, 0, debug_poll);
    //uv_check_init(p->loop, &check_watcher);
    //uv_check_start(&check_watcher, debug_check);

    return p;
}

/* create a slave kernel process */
void
kproc(char *name, void (*func)(void*), void *arg, int flags)
{
	uv_thread_t thread;
	kproc_t* p;
	Pgrp *pg;
	Fgrp *fg;
	Egrp *eg;
	Osdep *os;
    
    /* create a bare kernel proc */
	p = new_kproc();
    
    /* the hosting proc should be the same as the callers */
    p->hproc = up->hproc;
    
	if(p == nil)
		panic("kproc: no memory");

	os = malloc(sizeof(*os));
	if(os == nil) {
		panic("kproc: no memory for os dependencies");
    }
	p->os = os;
      
    /* initialize per-kproc os dependencies */
	os->self = 0;                               /* set by tramp */
    os->thread = nil;                           /* set by uv_thread_create */
    
	uv_sem_init(&os->sem, 0);
    
    /* copy optional parent environment */
	if(flags & KPDUPPG) {
		pg = up->env->pgrp;
		incref(&pg->r);
		p->env->pgrp = pg;
	}
    
	if(flags & KPDUPFDG) {
		fg = up->env->fgrp;
		incref(&fg->r);
		p->env->fgrp = fg;
	}
	if(flags & KPDUPENVG) {
		eg = up->env->egrp;
		incref(&eg->r);
		p->env->egrp = eg;
	}

    /* copy parent user info */
	p->env->uid = up->env->uid;
	p->env->gid = up->env->gid;
	kstrdup(&p->env->user, up->env->user);

	strcpy(p->text, name);

    /* patch in start function  */
	p->func = func;
    p->arg = arg;
    
    /* update the proc list */
	lock(&procs.l);
	if(procs.tail != nil) {
		p->prev = procs.tail;
		procs.tail->next = p;
	} else {
		procs.head = p;
		p->prev = nil;
	}
	procs.tail = p;
	unlock(&procs.l);

	if(uv_thread_create(&os->thread, tramp, p))
		panic("kernel thread create failed\n");
        
}

/* oshostintr is meant to unblock the thread that Proc p
 * is running on.  since this is highly dependent on the dis
 * process model (which we dont use), we'll have to remap it
 * to unsleep from a libuv event loop wait and sweep through
 * the scheduler and event list, perhaps performing a flush
 * operation on a recent request.  perhaps deleting its use
 * everywhere.  for now just return. 
 */

void
oshostintr(kproc_t *p)
{
    
	Osdep *os;

	os = p->os;
    /* send a USR1 signal to the proc */
	/*if(os != nil && os->self != 0)
		pthread_kill(os->self, SIGUSR1); */
    
}

/* more of the same.  this controls the wait acquisition
 * of a os resource or response.  this is probably eliminated
 * by async worker synchro in libuv
 */
void
osblock(void)
{
    
    Osdep *os;

    // get the hosting proc of this proc
    //hproc_t* hp = up->hproc;
    
    // get it's sync sem
	//os = hp->os;
	os = ((kproc_t*)up)->os;
    //print("osblock/sem_wait: on %p\n",os->sem);
	//while(sem_wait(&os->sem))
	//	{}
    uv_sem_wait(&os->sem);
    /* retry on signals (which shouldn't happen) */
}

/* the same */
void
osready(kproc_t* p)
{
	
    Osdep *os;

    //hproc_t* hp = up->hproc;
    
	//os = hp->os;
	os = p->os;
    //print("osready/sem_post: on %p\n",os->sem);
    //sem_post(&os->sem);
	uv_sem_post(&os->sem);
}

/* initialize thread local key for the base kernel proc */
void
baseinit(hproc_t* p)
{
    if(uv_key_create(&prdakey))
        panic("TLS key create failed");
    uv_key_set(&prdakey, p);
}


void
osyield(void)
{

    /* this is usually called by spinlocks when the spincycle has expired and they
     * want to try again later.  on a POSIX compliant OS this is usually achieved by calling
     * the generic sched_yield().  on windows you call SwitchToThread().  this should be
     * built into libuv.  until then we use sched_yield and cross fingers
     */
	sched_yield();
}

/* this is called by procs that want to decrease the priority of themselves or a
 * new child process.  essentially a nice function.  since we're single threaded 
 * and use fibers, its implementation dependent.  all fibers are scheduled
 * at a higher priority than background I/O anyway so that doesnt apply.  however
 * worker threads or custom background threads could receive similar scheduling
 * tweaks.  that would be pretty straightforward.  The only known use right now
 * is in the "cmd" function call which allows the user to specify a "nice" level.
 */
void
oslopri(void)
{
    /*
	struct sched_param param;
	int policy;
	pthread_t self;

	self = pthread_self();
	pthread_getschedparam(self, &policy, &param);
	param.sched_priority = sched_get_priority_min(policy);
	pthread_setschedparam(self,  policy, &param);
    */
}


