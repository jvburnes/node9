#include "nine.h"
#include	<interp.h>
#include	"raise.h"

/*
 * VM SUPPORT CODE FOR THE INFERNO SIDE OF THE LUA VM
 * 
 * (many of these functions manipulate critical kernel and vm structures and require a lock on isched.l)
 *
 */

int                 keepbroken = 1;
extern int          vflag;
static vproc_t**    pidlook(int);
static Progs*       delgrp(vproc_t*);
static void         addgrp(vproc_t*, vproc_t*);
void                printgrp(vproc_t*, char*);

char exNomem[]		 = "out of memory: main";

static vproc_t**
pidlook(int pid)
{
        ulong h;
        vproc_t **l;

        h = (ulong)pid % nelem(up->hproc->proghash);
        for(l = &(up->hproc->proghash[h]); *l != nil && (*l)->pid != pid; l = &(*l)->pidlink)
                ;
        return l;
}


/* create a new VM proc from parent proc p */
vproc_t*
new_vproc(proc_t* p, int flags)
{
	vproc_t* n;
    vproc_t** ph;
    hproc_t* hp;
	Osenv* on, * op;
    Pgrp* pg;
    Fgrp* fg;
    Egrp* eg;

    /* the inferno model simply creates a new virtual proc by sharing
     * the os environment of the parent. this environment can be modified 
     * by later calls to sys-pctl to fork the various environment components
     * or start fresh 
     */

    if (p != nil && p->ptype == Kern_proc) {
        panic("invalid parent process type");
    }
   
    hp = p->hproc;
    
    /* create the vproc and patch in default env buffer */
	n = malloc(sizeof(vproc_t));
	if(n == 0){
		if(p == nil)
			panic("no memory");
		else
			error(exNomem);
	}
    n->env = &(n->defenv);
    
    /* we are a vm proc */
    n->ptype = Vm_proc;
    
    /* record hosting kproc */
    n->hproc = hp;

    /* setup err buffers and initialize username */
	kstrdup(&n->env->user, "*nouser");
	n->env->errstr = n->env->errbuf0;
	n->env->syserrstr = n->env->errbuf1;

    /* initialize the quanta and proc flags */
	n->quanta = PQUANTA;
	n->flags = 0;
    
	n->pid = ++(hp->pidnum);   
    
	if(n->pid <= 0) {
		panic("no pids");
    }
	n->group = nil;

    /* place in prog table and get handle */
    ph = pidlook(n->pid);
    if(*ph != nil) {
        panic("dup pid");
    }
    n->pidlink = nil;
    *ph = n;

    /* init the proc environment depending on the parent type */
    if (p != nil) {
        switch (p->ptype) {
        case Host_proc:
            /* copy optional parent kernel components */
            if(flags & KPDUPPG) {
                pg = p->env->pgrp;
                incref(&pg->r);
                n->env->pgrp = pg;
                kstrdup(&n->env->user, p->env->user);
            }
            if(flags & KPDUPFDG) {
                fg = p->env->fgrp;
                incref(&fg->r);
                n->env->fgrp = fg;
            }
            if(flags & KPDUPENVG) {
                eg = p->env->egrp;
                incref(&eg->r);
                n->env->egrp = eg;
            }
            /* copy host user info */
            n->env->uid = p->env->uid;
            n->env->gid = p->env->gid;

            /* since this proc has no one to group with ... */
            newgrp(n);
            
            break;
        
        case Vm_proc:
        {
            vproc_t* vp = (vproc_t*)p;  // up cast parent to vproc
            
            /* add to parent's group */
           	addgrp(n, vp);
            
            /* copy parent flags */
            n->flags = vp->flags;
            if(vp->flags & Prestrict)
                n->flags |= Prestricted;
                
            /* copy parent os environment completely */
            memmove(n->env, vp->env, sizeof(Osenv));
            op = vp->env;
            on = n->env;
            
            /* the new vproc will wait on the parents child q */
            on->waitq = op->childq;
            
            /* take refs on all shared structures */
            incref(&on->pgrp->r);
            incref(&on->fgrp->r);
            incref(&on->egrp->r);
            
            /* share the signature set */
            if(on->sigs != nil)
                incref(&on->sigs->r);
            
            /* copy the user info and error buffers */
            on->user = nil;
            kstrdup(&on->user, op->user);
            on->uid = op->uid;
            on->gid = op->gid;
            on->errstr = on->errbuf0;
            on->syserrstr = on->errbuf1;

            /* update parent flags / shared kill from group */
            if(vp->group != nil)
                vp->flags |= vp->group->flags & Pkilled;
            if(vp->kill != nil)
                error(vp->kill);
            if(vp->flags & Pkilled)
                error("");
            break;
        }
            
        default:
            panic("invalid parent process type");
        }
    }
    else {
        /* otherwise its a loner, so place it into a new group */
        newgrp(n);
    }

    trace(TRACE_WARN,"created vproc %p with pid %ld",n,n->pid);
	return n;
}


vproc_t*
progpid(int pid)
{
        return *pidlook(pid);
}

/* remove program from process list */

void
delprog(vproc_t* p, char* msg)
{
	Osenv *o;
    vproc_t** ph;
    
	tellsomeone(p, msg);	/* call before being removed from prog list */

	o = p->env;
	closepgrp(o->pgrp);
	closefgrp(o->fgrp);
	closeegrp(o->egrp);
	closesigs(o->sigs);

	delgrp(p);
    
    /* unbind the process from its event interface */
    //uv_close(&p->swi_wake, NULL);

    /* remove process from proc list and hash table, move to sched.lua 
            if(p->prev)
                p->prev->next = p->next;
        else
                isched.head = p->next;

        if(p->next)
                p->next->prev = p->prev;
        else
                isched.tail = p->prev;

*/
    ph = pidlook(p->pid);
    if(*ph == nil)
            panic("lost pid");
    *ph = p->pidlink;

  /*      if(p == isched.runhd) {
                isched.runhd = p->link;
                if(p->link == nil)
                        isched.runtl = nil;
        }
    */
    
	p->state = 0xdeadbeef;
	free(o->user);
	free(p->killstr);
	free(p->exstr);
	free(p);
}

/* tell any of p's children or on it's waitq that "buf" event has occurred
 */
void
tellsomeone(vproc_t *p, char *buf)
{
	Osenv *o;

	if(waserror())
		return;
	o = p->env;
	if(o->childq != nil)
		qproduce(o->childq, buf, strlen(buf));
	if(o->waitq != nil) 
		qproduce(o->waitq, buf, strlen(buf)); 
	poperror();
}

/* software interrupt for prog, probably not necessary 
static void
swiprog(Prog *p)
{
	Proc *q;

	lock(&procs.l);
	for(q = procs.head; q; q = q->next) {
		if(q->iprog == p) {
			unlock(&procs.l);
			swiproc(q, 1);
			return;
		}
	}
	unlock(&procs.l);
}
*/

static vproc_t*
grpleader(vproc_t *p)
{
	Progs *g;
	vproc_t *l;

	g = p->group;
	if(g != nil && (l = g->head) != nil && l->pid == g->id)
		return l;
	return nil;
}

/****
 * exprog, propex and killprog all handle inferno-style single and group
 * process killing.  they account for state dependencies, resource release,
 * wait states, wake up, etc.  these will have to be tweaked for node9 and
 * much of it (if not all of it) will reside in the luajit scheduler.
 ****/
int
exprog(vproc_t *p, char *exc)
{
	/* similar code to killprog but not quite */
	switch(p->state) {
/*
	case Palt:
		altdone(p->R.s, p, nil, -1);
		break;
*/
	case Psend:
		//cqdelp(&p->chan->send, p);
		break;
	case Precv:
		//cqdelp(&p->chan->recv, p);
		break;
	case Pready:
		break;
/*
	case Prelease:
		swiprog(p);
		break;
*/
	case Pexiting:
	case Pbroken:
	case Pdebug:
		return 0;
	default:
		panic("exprog - bad state 0x%x\n", p->state);
	}
/*	if(p->state != Pready && p->state != Prelease)
		addrun(p);
*/
	if(p->kill == nil){
		if(p->killstr == nil){
			p->killstr = malloc(ERRMAX);
			if(p->killstr == nil){
				p->kill = Enomem;
				return 1;
			}
		}
		kstrcpy(p->killstr, exc, ERRMAX);
		p->kill = p->killstr;
	}
	return 1;
}

static void
propex(vproc_t *p, char *estr)
{
	vproc_t *f, *nf, *pgl;

	if(!(p->flags & (Ppropagate|Pnotifyleader)) || p->group == nil)
		return;
	if(*estr == 0){
		if((p->flags & Pkilled) == 0)
			return;
		estr = "killed";
	}
	pgl = grpleader(p);
	if(pgl == nil)
		pgl = p;
	if(!(pgl->flags & (Ppropagate|Pnotifyleader)))
		return;	/* exceptions are local; don't propagate */
	for(f = p->group->head; f != nil; f = nf){
		nf = f->grpnext;
		if(f != p && f != pgl){
			if(pgl->flags & Ppropagate)
				exprog(f, estr);
			else{
				f->flags &= ~(Ppropagate|Pnotifyleader);	/* prevent recursion */
				killprog(f, "killed");
			}
		}
	}
	if(p != pgl)
		exprog(pgl, estr);
}

int
killprog(vproc_t *p, char *cause)
{
	Osenv *env;
	char msg[ERRMAX+2*KNAMELEN];

	if(p == (vproc_t*) up) {
		p->kill = "";
		p->flags |= Pkilled;
		p->state = Pexiting;
		return 0;
	}

	switch(p->state) {
/*	case Palt:
		altdone(p->R.s, p, nil, -1);
		break;
*/
	case Psend:
		//cqdelp(&p->chan->send, p);
		break;
	case Precv:
		//cqdelp(&p->chan->recv, p);
		break;
	case Pready:
        /* luv should do this */
		/* delrunq(p); */
		break;
/*
	case Prelease:
		p->kill = "";
		p->flags |= Pkilled;
		p->state = Pexiting;
		swiprog(p);
*/
	case Pexiting:
		return 0;
	case Pbroken:
	case Pdebug:
		break;
	default:
		panic("killprog - bad state 0x%x\n", p->state);
	}

/*	if(p->addrun != nil) {
		p->kill = "";
		p->flags |= Pkilled;
		p->addrun(p);
		p->addrun = nil;
		return 0;
	}
*/
	env = p->env;
	if(env->debug != nil) {
		p->state = Pbroken;
		//dbgexit(p, 0, cause);  // this is a call into devprog
		return 0;
	}

	propex(p, "killed");

	snprint(msg, sizeof(msg), "%d \"%s\":%s", p->pid, p->text, cause);

	p->state = Pexiting;
    
    /* dis-specific stuff */
    
    /*
	gclock();
	destroystack(&p->R);
    */
	delprog(p, msg);
    /*
	gcunlock();
    */
	return 1;
}

void
newgrp(vproc_t* p)
{
	Progs *pg, *g;

	if(p->group != nil && p->group->id == p->pid)
		return;
	g = malloc(sizeof(*g));
	if(g == nil)
		error(Enomem);
	p->flags &= ~(Ppropagate|Pnotifyleader);
	g->id = p->pid;
	g->flags = 0;
	if(p->group != nil)
		g->flags |= p->group->flags&Pprivatemem;
	g->child = nil;
	pg = delgrp(p);
	g->head = g->tail = p;
	p->group = g;
	if(pg != nil){
		g->sib = pg->child;
		pg->child = g;
	}
	g->parent = pg;
}

static void
addgrp(vproc_t *n, vproc_t *p)
{
	Progs *g;

	n->group = p->group;
	if((g = n->group) != nil){
		n->grpnext = nil;
		if(g->head != nil){
			n->grpprev = g->tail;
			g->tail->grpnext = n;
		}else{
			n->grpprev = nil;
			g->head = n;
		}
		g->tail = n;
	}
}

/* removes p from the process group, adjusts subgroups and returns 
 * the prog group of this process
 */
static Progs*
delgrp(vproc_t* p)
{
	Progs *g, *pg, *cg, **l;

	g = p->group;
    
    /* remove p from the proc group */
	if(g == nil)
		return nil;
	if(p->grpprev)
		p->grpprev->grpnext = p->grpnext;
	else
		g->head = p->grpnext;
	if(p->grpnext)
		p->grpnext->grpprev = p->grpprev;
	else
		g->tail = p->grpprev;
	p->grpprev = p->grpnext = nil;
	p->group = nil;

    /* if group has no remaining procs */
	if(g->head == nil){
		/* move up, giving subgroups of groups with no procs to their parents */
		do{
			if((pg = g->parent) != nil){
				pg = g->parent;
				for(l = &pg->child; *l != nil && *l != g; l = &(*l)->sib)
					;
				*l = g->sib;
			}
			/* put subgroups in new parent group */
			while((cg = g->child) != nil){
				g->child = cg->sib;
				cg->parent = pg;
				if(pg != nil){
					cg->sib = pg->child;
					pg->child = cg;
				}
			}
			free(g);
		}while((g = pg) != nil && g->head == nil);
	}
	return g;
}

void
printgrp(vproc_t *p, char *v)
{
	Progs *g;
	vproc_t *q;

	g = p->group;
	print("%s pid %d grp %d pgrp %d: [pid", v, p->pid, g->id, g->parent!=nil?g->parent->id:0);
	for(q = g->head; q != nil; q = q->grpnext)
		print(" %d", q->pid);
	print(" subgrp");
	for(g = g->child; g != nil; g = g->sib)
		print(" %d", g->id);
	print("]\n");
}

/* kill all procs in the group specified by p */
int
killgrp(vproc_t *p, char *msg)
{
	int i, npid, *pids;
	vproc_t *f;
	Progs *g;

	/* interpreter has been acquired */
	g = p->group;
	if(g == nil || g->head == nil)
		return 0;
	
    /* Wait here if someone else is already cutting throats
     * (It's possible that they are being killed as new procs
     *  are joining group.  After leaving this loop, there 
     *  could be still be valid members.  Wouldn't it be
     *  possible that the size of it might be nil?
     */
    while(g->flags & Pkilled){
		//release();
		//acquire();
	}
    
    /* find group size and make sure they really are all in this group
     * (bad juju if not)
     */
	npid = 0;
	for(f = g->head; f != nil; f = f->grpnext)
		if(f->group != g)
			panic("killgrp");
		else
			npid++;
            
	/* collect the group members: record pids instead of pointers since
     * state can change during delprog phase 
     */
    
	pids = malloc(npid*sizeof(int));
	if(pids == nil)
		error(Enomem);
	npid = 0;
	for(f = g->head; f != nil; f = f->grpnext)
		pids[npid++] = f->pid;

    /* protect the kill phase, so nobody else tries doing this at same time */
	g->flags |= Pkilled;
    
    /* try/catch here if it doesn't work */
	if(waserror()) {
        /* oops, something blew up.  get out of kill phase, and recover */
		g->flags &= ~Pkilled;
		free(pids);
		nexterror();
	}
    
    /* kill each pid */
	for(i = 0; i < npid; i++) {
		f = progpid(pids[i]);
        /* if proc exists and its not the currently executing one, kill it */
		if(f != nil && f != (vproc_t*)up)
			killprog(f, msg);
	}
    
    /* end of try */
	poperror();
    
    /* no longer killing, so unlock and free resources */
	g->flags &= ~Pkilled;
	free(pids);
	return 1;
}

char	changup[] = "channel hangup";

/*
void
killcomm(Progq **q)
{
	Prog *p;
	Progq *f;

	for (f = *q; f != nil; f = *q) {
		*q = f->next;
		p = f->prog;
		free(f);
		if(p == nil)
			return;
		p->ptr = nil;
		switch(p->state) {
		case Prelease:
			swiprog(p);
			break;
		case Psend:
		case Precv:
			p->kill = changup;
			addrun(p);
			break;
		case Palt:
			altgone(p);
			break;
		}
	}
}

*/

static void
cwakeme(vproc_t *p)
{
	Osenv *o;

	//p->addrun = nil;
	o = p->env;
	// dont think we need this right away
    //Wakeup(o->rend);
}

static int
cdone(vproc_t *vp)
{
	vproc_t* p = vp;

	return p->kill != nil;
}

void
cblock(vproc_t *p)
{
}

/* currun:
 *    returns:
 *      - the virtual process executing in the calling thread 
 *      - nil, if we're running in the kernel
 */
vproc_t*
currun()
{
    if (up->ptype != Vm_proc) return nil;
    return (vproc_t*)up;
}

/*
 * if the vproc 'r' is under debug, progexit performs breakpoint processing,
 * otherwise it just cleans up and deletes the vproc
 */
void
progexit(vproc_t* r)
{
	int broken;
	char *estr, msg[ERRMAX+2*KNAMELEN];

    /* 'r' is the currently running proc.  since that's the same as 'up' in node9
     * we capture it once and use it during the entire function
     */
	
    trace(TRACE_WARN,"exiting vproc %p with pid %ld",r,r->pid);
    estr = r->env->errstr;
    broken = 0;
	
    if(estr[0] != '\0' && strcmp(estr, Eintr) != 0 && strncmp(estr, "fail:", 5) != 0)
    {
		broken = 1;
    }

	if(*estr == '\0' && r->flags & Pkilled)
    {
		estr = "killed";
    }
    
	if(broken){
		print("[%s] Broken: \"%s\"\n", r->text, estr);
	}

	snprint(msg, sizeof(msg), "%d \"%s\":%s", r->pid, r->text, estr);

    /* if debugger active, then compensate */
	if(r->env->debug != nil) {
		//dbgexit(r, broken, estr);
		broken = 1;
		/* must force it to break if in debug */
	}
    else if(broken && (!keepbroken || strncmp(estr, "out of memory", 13)==0 || memusehigh())) {
        /* if can't support debug operations */
		broken = 0;	/* don't want them or short of memory */
    }

    /* if the combination of settings results in a breakpoint, then tell whomever is listening and
     * don't exit yet
     */
	if (broken) {
		tellsomeone(r, msg);
		r->state = Pbroken;
		return;
	}

    /* else we didn't break, so just release the vproc */
 	delprog(r, msg);
}
