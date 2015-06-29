#include "nine.h"
#include "interp.h"

// shared library binds to the inferno version of these
#define malloc(x) imalloc(x)
#define free(x) ifree(x)
#define calloc(x,y) icalloc(x,y)
#define realloc(x,y) irealloc(x,y)

// appears to check for fd (x) existence
//#define fdchk(x)	((x) == (Sys_FD*)H ? -1 : (x)->fd)
#define fdchk(x) ((x) == nil ? -1 : (x)->fd)

// worker/responder prototypes

void worker_done(uv_work_t*, int);
void sys_sleep_expired(uv_timer_t*);
static int waiting_procs;

struct FD
{
	Sys_FD	fd;
	Fgrp*	grp;
};

void
sysinit(void)
{
/*	TFD = dtype(freeFD, sizeof(FD), FDmap, sizeof(FDmap));
	TFileIO = dtype(freeFileIO, Sys_FileIO_size, FileIOmap, sizeof(FileIOmap));

	// Support for devsrv.c
	FioTread = dtype(freeheap, Sys_FileIO_read_size, rmap, sizeof(rmap));
	FioTwrite = dtype(freeheap, Sys_FileIO_write_size, wmap, sizeof(wmap));

	// Support for dirread
	Tdir = dtype(freeheap, Sys_Dir_size, dmap, sizeof(dmap));
*/
}

/* svc_events:
 *  run a single pass of the libuv event loop
 *  - if node9 has ready tasks, it tells libuv to come back ASAP
 *  - otherwise, it just wait's for event and I/O callbacks so the host can
 *    do other things
 */
void
svc_events(int ready_vprocs)
{    
    hproc_t* hp = (hproc_t*) up;
    trace(TRACE_DEBUG, "servicing events");

    /* save the ready vproc state for later */
    waiting_procs = ready_vprocs;
        
    uv_run(hp->loop, UV_RUN_ONCE);
 }
 
/******************** UTILITY FUNCTIONS **************/


/* this executes in the kernel context and just returns the identity of
 * vproc for process id 'pid' 
 */
vproc_t* progpid(int pid);      // for kernel function

void* 
procpid(int pid)
{
    // get a temp lock on the proc table
    hproc_t* hp = (hproc_t*) up;
    vproc_t* vp;
    
    lock(&hp->isched.l);
    vp = progpid(pid);
    unlock(&hp->isched.l);
    return vp;
}

/* return the address of the system call buffer */
N9SysReq* 
sysbuf(void* p)
{
    return &(((vproc_t*)p)->sreq);
}

int
pidproc(void *vp)
{
    return ((vproc_t*)vp)->pid;
}


/******************** FINALIZERS / DECONSTRUCTORS / DEALLOCATORS **************/

void FreeFD(uv_work_t* wreq);

void
vproc_exit(void* vp)
{    
    vproc_t* p = vp;
    hproc_t* hp = p->hproc;
    
    // (first clear the error buffer)
    p->env->errstr = "";

    // release the specified vproc resources and shut it down
    lock(&p->hproc->isched.l);
    progexit(p);
    unlock(&hp->isched.l);

}

void
free_cstring(char* cstr)
{
    free(cstr);
}

void
free_dir(Dir* dir)
{
    free(dir);
}

void
free_fd(Sys_FD *fd)
{
    if (!fd) return;
    
    trace(TRACE_DEBUG, "freeing fdes %d @ %p",fd->fd, fd);

    // upcast the Sys_FD back to the augmented FD
    FD* Fd = (FD*)fd;
        
    // release the fdes and any groups 
	if(Fd->fd.fd >= 0)
		kfgrpclose(Fd->grp, Fd->fd.fd);
	closefgrp(Fd->grp);
    
    // we created it, so we need to release it
    free(Fd);

}

void
free_dirpack(Dirpack* dpack)
{
    trace(TRACE_WARN, "kern: freeing dirpack @ %p of length %ld",dpack,dpack->num);
    if (dpack->num) free(dpack->dirs);
    free(dpack); 
}

void
free_sysconn(Sys_Connection* sysconn)
{
    trace(TRACE_WARN, "kern: freeing Sys_Connection @ %p",sysconn);
    free_fd(sysconn->dfd);  // release the file handles
    free_fd(sysconn->cfd);
    free(sysconn->dir);     // release the path
    free(sysconn);          // the structure itself
}

/*void
freeFileIO(Heap *h, int swept)
{
	Sys_FileIO *fio;

	if(swept)
		return;

	fio = H2D(Sys_FileIO*, h);
	destroy(fio->read);
	destroy(fio->write);
}
*/

/* create an augmented fd with a ref on the file grp so we can release it later */
Sys_FD*
mkfd(int fd)
{
	FD* fdes = (FD*) malloc(sizeof(FD));
    fdes->fd.fd = fd;
	Fgrp* fg = up->env->fgrp;
	fdes->grp = fg;
	incref(&fg->r);
	return (Sys_FD*)fdes;
}

// sets errstr in process p
void
seterror(proc_t* p, char *err, ...)
{
	char *estr;
	va_list arg;

	estr = p->env->errstr;
	va_start(arg, err);
	vseprint(estr, estr+ERRMAX, err, arg);
	va_end(arg);
}

// places current errstr into 's'
char*
syserr(char *s, char *es, vproc_t *p)
{
	Osenv *o;

	o = p->env;
	kstrcpy(s, o->errstr, es - s);
	return s + strlen(s);
}

/******************** SYSCALL INTERFACE ****************************/

/* the primary sysreq call.  the only parameters are the calling vproc and request
 * the request and return values are taken from the processes sreq buffer.
 * this works because there is only sysreq call active at a time per process
 *
 * this just queues the call for the dispatcher to retrieve later
 */
void sysreq(void *p,void (*scall)(void*))
{
    hproc_t* hp = (hproc_t*) up;                // get hosting kernel proc
    vproc_t* vp = p;
    
    trace(TRACE_DEBUG, "issuing sys request");
    N9SysReq* sreq = &vp->sreq;   // the vprocs sysreq buff
    sreq->req.proc = p;
    sreq->req.scall = scall;

    // queue the sysreq
    // init request node
    QUEUE_INIT(&vp->node);
    QUEUE_INSERT_TAIL(&hp->reqq, &vp->node);
    trace(TRACE_DEBUG, "issued sys request");
}

/* this is the default 'after callback'.  it runs in kernel context after the event loop wakes */
void 
worker_done(uv_work_t* workreq, int status)
{
    // this always runs in kernel context
    hproc_t* hp = (hproc_t*)up;
    
    // first recover the process
    vproc_t *vp = (vproc_t *) container_of(workreq, vproc_t, worker);
   
    // recover from interruption if necessary
    if (status < 0) {
        // set the error string in the vproc to "Interrupted"
        seterror((proc_t*)vp, Eintr);
    }
    // return result on reply queue
    // init reply node
    QUEUE_INIT(&vp->node);
    QUEUE_INSERT_TAIL(&hp->repq, &vp->node);
    N9SysReq* sreq = &(vp->sreq);
    trace(TRACE_DEBUG,"******** worker done ***********");
}

/* the scheduler calls this to dequeue the pid of the next ready reply */
int
sysrep()
{
    hproc_t* hp = (hproc_t*) up;
    trace(TRACE_WARN,"sysrep: examining reply queue of kernel process %p",hp);
    // return the pid of the oldest pending reply or zero if empty
    if (QUEUE_EMPTY(&hp->repq)) { return 0; }
    
    QUEUE* q = QUEUE_HEAD(&hp->repq);
    QUEUE_REMOVE(q);
    vproc_t* vp = QUEUE_DATA(q, vproc_t, node);
    return vp->pid;
}


/******************** SYSCALLS ****************************/

void
Sys_open(uv_work_t* workreq)
{
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
    // perform the open logic
    sreq->open.ret = nil;
    int fd = kopen(sreq->open.s, sreq->open.mode);  
    
    // if we have a good fdes, augment it with it's filegroup
	if(fd != -1) {
		sreq->open.ret = mkfd(fd);
    } else {
        trace(TRACE_WARN,"Sys_open: file open failed because '%s' or '%s'",vp->env->syserrstr, vp->env->errstr);
    }
    
    
}

void
Sys_create(uv_work_t* workreq)
{
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
	sreq->create.ret = nil;
	int fd = kcreate(sreq->create.s, sreq->create.mode, sreq->create.perm);

    if (fd != -1) {
        // we have a good fdes, augment it with it's filegroup
        sreq->create.ret = mkfd(fd);
    }
    
    if (fd == -1) {
        trace(TRACE_WARN,"Sys_create: failed because '%s' or '%s'",vp->env->syserrstr, vp->env->errstr);
    }
    
}


/*
void
Sys_pipe(void *fp)
{
	Array *a;
	int fd[2];
	Sys_FD **sfd;
	F_Sys_pipe *f;

	f = fp;
	*f->ret = -1;

	a = f->fds;
	if(a->len < 2)
		return;
	if(kpipe(fd) < 0)
		return;

	sfd = (Sys_FD**)a->data;
	destroy(sfd[0]);
	destroy(sfd[1]);
	sfd[0] = H;
	sfd[1] = H;
	sfd[0] = mkfd(fd[0]);
	sfd[1] = mkfd(fd[1]);
	*f->ret = 0;
}


*/

void
Sys_dup(uv_work_t* workreq)
{
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
	sreq->dup.ret = kdup(sreq->dup.old, sreq->dup.new);	
    
    

}

void
Sys_fildes(uv_work_t* workreq)
{
    int fd;
    
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
    sreq->fildes.ret = NULL;
    
	fd = kdup(sreq->fildes.fd, -1);	
	if(fd == -1)
		return;
        
	sreq->fildes.ret = mkfd(fd);
    
    
}

void
Sys_remove(uv_work_t* workreq)
{
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
	sreq->remove.ret = kremove(sreq->remove.s);

}

void
Sys_seek(uv_work_t* workreq)
{
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
	sreq->seek.ret = kseek(fdchk(sreq->seek.fd), sreq->seek.off, sreq->seek.start);

}


/* read up to n bytes from file fd into the byte buffer */
void
Sys_read(uv_work_t* workreq)
{
	int n;

    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
 	n = sreq->read.nbytes;
	if (sreq->read.buf == nil || n < 0) {
		sreq->read.ret = 0;
	}
    else {        
        if(n > sreq->read.buf->alloc) { n = sreq->read.buf->alloc; }
        sreq->read.ret = kread(fdchk(sreq->read.fd), sreq->read.buf->content, n);
        sreq->read.buf->length = sreq->read.ret;
    }
 
}

/* read exactly n bytes from file fd into the byte buffer */
void
Sys_readn(uv_work_t* workreq)
{
	int fd, m, n, t;

    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);

	n = sreq->readn.n;
	if (sreq->readn.buf == nil || n < 0) {
		sreq->readn.ret = 0;
	}
	else {
        if(n > sreq->readn.buf->alloc) { n = sreq->readn.buf->alloc; }
        fd = fdchk(sreq->readn.fd);
        for (t = 0; t < n; t += m) {
            m = kread(fd, (char*)sreq->readn.buf->content+t, n-t);
            if (m <= 0) {
                if(t == 0)
                    t = m;
                break;
            }
        }
	    sreq->readn.ret = t;
        sreq->readn.buf->length = t;
    }    
}

/* read up to n bytes from file fd at offset off into the byte buffer */
void
Sys_pread(uv_work_t* workreq)
{
	int n;
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);

	n = sreq->pread.n;
	if (sreq->pread.buf == nil || n < 0) {
		sreq->pread.ret = 0;
	}
	else {
        if (n > sreq->pread.buf->alloc) { n = sreq->pread.buf->alloc; }
        sreq->pread.ret = kpread(fdchk(sreq->pread.fd), sreq->pread.buf->content, n, sreq->pread.off);
        sreq->read.buf->length = sreq->read.ret;
    }

}


void
Sys_chdir(uv_work_t* workreq)
{
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);

	sreq->chdir.ret = kchdir(sreq->chdir.path);    
}

/* writes up to n chars from byte buffer into fd */
void
Sys_write(uv_work_t* workreq)
{
	int n;
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
 	n = sreq->write.nbytes;
	if (sreq->write.buf == nil || n < 0) {
		sreq->write.ret = 0;
	}
    else {
        if(n > sreq->write.buf->alloc) {
            n = sreq->write.buf->alloc;
        }
        sreq->write.ret = kwrite(fdchk(sreq->write.fd), sreq->write.buf->content, n);
    }

}

/* write n bytes in byte buffer to fd at offset off */
void
Sys_pwrite(uv_work_t* workreq)
{
	int n;
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
	n = sreq->pwrite.n;
	if (sreq->pwrite.buf == nil || n < 0) {
		sreq->pwrite.ret = 0;
	}
    else {
        if (n > sreq->pread.buf->alloc) { n = sreq->pread.buf->alloc; }
        sreq->pwrite.ret = kpwrite(fdchk(sreq->pwrite.fd), sreq->pwrite.buf->content, n, sreq->pwrite.off);
        sreq->pwrite.buf->length = sreq->pwrite.ret;
    }    
}


void
Sys_fstat(uv_work_t* workreq)
{
	Dir *d;
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
    sreq->fstat.ret = nil;
    
	d = kdirfstat(fdchk(sreq->fstat.fd));
	if(d == nil) { return; }
        
	if(waserror() == 0) {
		sreq->fstat.ret = d;
		poperror();
	}    

}

void
Sys_stat(uv_work_t* workreq)
{
	Dir *d;
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
    sreq->stat.ret = nil;
    
	d = kdirstat(sreq->stat.s);
	if(d == nil) { return; }
        
	if(waserror() == 0) {
		sreq->stat.ret = d;
		poperror();
	}    
  
}

void
Sys_wstat(uv_work_t* workreq)
{
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
	sreq->wstat.ret = kdirwstat(sreq->wstat.s, sreq->wstat.dir);
    
}

void
Sys_fwstat(uv_work_t* workreq)
{
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
	sreq->fwstat.ret = kdirfwstat(fdchk(sreq->fwstat.fd), sreq->fwstat.dir);

}

void
Sys_fd2path(uv_work_t* workreq)
{
	char *s;
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
	s = kfd2path(fdchk(sreq->fd2path.fd));
	if(waserror() == 0){
		sreq->fd2path.ret = s;
		poperror();
	}
    
}

void
Sys_bind(uv_work_t* workreq)
{
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
    // bind is very simple
	sreq->bind.ret = kbind(sreq->bind.name, sreq->bind.on, sreq->bind.flags);
    
}

void
Sys_mount(uv_work_t* workreq)
{
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
	sreq->mount.ret = kmount(fdchk(sreq->mount.fd), fdchk(sreq->mount.afd), sreq->mount.on, sreq->mount.flags, sreq->mount.spec);
    
}

void
Sys_unmount(uv_work_t* workreq)
{
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
    // unmount is very simple
	sreq->unmount.ret = kunmount(sreq->unmount.name, sreq->unmount.from);
    
}

void
Sys_print(uv_work_t* workreq)
{
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
    // write to stdout
    sreq->print.ret = kwrite(1, sreq->print.buf, sreq->print.len);
   
}

void
Sys_fprint(uv_work_t* workreq)
{
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
    // write to fd
    sreq->fprint.ret = kwrite(fdchk(sreq->fprint.fd), sreq->fprint.buf, sreq->fprint.len);
    
}

/* just return the last error string */
char* 
sys_errstr(void *p)
{
    return ((vproc_t*)p)->env->errstr;
}


void
sys_werrstr(void *p, char* err)
{
	kstrcpy(((proc_t*)p)->env->errstr, err, ERRMAX);
}


void
Sys_dial(uv_work_t* workreq)
{
	int cfd;

    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
 
    // perform the dial logic
    sreq->dial.ret = nil;
    char *dir = malloc(NETPATHLEN);
    
	int fd = kdial(sreq->dial.d_addr, sreq->dial.d_local, dir, &cfd);
    
    // if we have a good fdes, create the connection structure
    if(fd != -1) {
        // configure a Sys_Connection return structure
        Sys_Connection* sc = (Sys_Connection*)malloc(sizeof(Sys_Connection));
        sreq->dial.ret = sc;

        sc->dfd = mkfd(fd);
        sc->cfd = mkfd(cfd);
        sc->dir = dir; 
        
    } else {
        free(dir);
        trace(TRACE_WARN,"Sys_dial: connect failed because '%s' or '%s'",vp->env->syserrstr, vp->env->errstr);
    }
    
}

void
Sys_announce(uv_work_t* workreq)
{
	int cfd;

    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
 
    // perform the announce logic
    sreq->announce.ret = nil;
    char *dir = malloc(NETPATHLEN);
    
	int fd = kannounce(sreq->announce.d_addr, dir);
    
    // if we have a good fdes, create the connection structure
    if(fd != -1) {
        // configure a Sys_Connection return structure
        Sys_Connection* sc = (Sys_Connection*)malloc(sizeof(Sys_Connection));
        sreq->announce.ret = sc;

        sc->dfd = nil;
        sc->cfd = mkfd(fd);
        sc->dir = dir; 
        
    } else {
        free(dir);
        trace(TRACE_WARN,"Sys_announce: announce failed because '%s' or '%s'",vp->env->syserrstr, vp->env->errstr);
    }
    
}

void
Sys_listen(uv_work_t* workreq)
{
	int cfd;

    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
 
    // perform the listen logic
    sreq->listen.ret = nil;
    char *dir = malloc(NETPATHLEN);
    
	int fd = klisten(sreq->listen.conn->dir, dir);
    
    // if we have a good fdes, create the connection structure
    if(fd != -1) {
        // configure a Sys_Connection return structure
        Sys_Connection* sc = (Sys_Connection*)malloc(sizeof(Sys_Connection));
        sreq->listen.ret = sc;

        sc->dfd = nil;
        sc->cfd = mkfd(fd);
        sc->dir = dir; 
        
    } else {
        free(dir);
        trace(TRACE_WARN,"Sys_listen: announce failed because '%s' or '%s'",vp->env->syserrstr, vp->env->errstr);
    }
    
}

/* sys.sleep interface
 * this eventually calls through the osenter/leave to libuv, so lets skip the drama and do it
 */
void
sys_sleep(void* p, int msecs)
{
    vproc_t* vp = (vproc_t*)p;
    N9SysReq* sreq = &vp->sreq;   // the vprocs syscall buff
    hproc_t* hp = (hproc_t*) up;   // get hosting kernel proc   

    // marshall the call parameters
    sreq->req.proc = p;
    sreq->sleep.period = msecs;

    // and dispatch the one-shot timer directly through the vproc ticker
    uv_timer_init(hp->loop, &vp->ticker);
    uv_timer_start(&vp->ticker, sys_sleep_expired, msecs, 0);
    
    // wait for it to fire
}

void
sys_sleep_expired(uv_timer_t* treq)
{
    hproc_t* hp = (hproc_t*) up;

    // retrive the vproc
    vproc_t* vp = (vproc_t*) container_of(treq, vproc_t, ticker);
    // retrieve the sys request
    N9SysReq* sreq = &vp->sreq;
    
    // dummy status
    sreq->sleep.ret = 0;
    
    trace(TRACE_DEBUG, "sleep expired after %d msecs",sreq->sleep.period);
    // reply
    QUEUE_INIT(&vp->node);
    QUEUE_INSERT_TAIL(&hp->repq, &vp->node); 
}

/*
void
Sys_stream(void *fp)
{
	Prog *p;
	uchar *buf;
	int src, dst;
	F_Sys_stream *f;
	int nbytes, t, n;

	f = fp;
	buf = malloc(f->bufsiz);
	if(buf == nil) {
		kwerrstr(Enomem);
		*f->ret = -1;
		return;
	}

	src = fdchk(f->src);
	dst = fdchk(f->dst);

	p = currun();

	release();
	t = 0;
	nbytes = 0;
	while(p->kill == nil) {
		n = kread(src, buf+t, f->bufsiz-t);
		if(n <= 0)
			break;
		t += n;
		if(t >= f->bufsiz) {
			if(kwrite(dst, buf, t) != t) {
				t = 0;
				break;
			}

			nbytes += t;
			t = 0;
		}
	}
	if(t != 0) {
		kwrite(dst, buf, t);
		nbytes += t;
	}
	acquire();
	free(buf);
	*f->ret = nbytes;
}
*/

void
Sys_export(uv_work_t* workreq)
{
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
	sreq->export.ret = export(fdchk(sreq->export.fd), sreq->export.dir, sreq->export.flag);
    
}

/*
void
Sys_file2chan(void *fp)
{
	int r;
	Heap *h;
	Channel *c;
	Sys_FileIO *fio;
	F_Sys_file2chan *f;
	void *sv;

	h = heap(TFileIO);

	fio = H2D(Sys_FileIO*, h);

	c = cnewc(FioTread, movtmp, 16);
	fio->read = c;

	c = cnewc(FioTwrite, movtmp, 16);
	fio->write = c;

	f = fp;
	sv = *f->ret;
	*f->ret = fio;
	destroy(sv);

	release();
	r = srvf2c(string2c(f->dir), string2c(f->file), fio);
	acquire();
	if(r == -1) {
		*f->ret = H;
		destroy(fio);
	}
}

*/
enum
{
	/* the following pctl calls can block and must release the virtual machine */
	BlockingPctl=	Sys_NEWFD|Sys_FORKFD|Sys_NEWNS|Sys_FORKNS|Sys_NEWENV|Sys_FORKENV
};


void*
make_vproc(void* pproc)
{
    vproc_t* nvp = nil;
    hproc_t* hp = (hproc_t*) up;
    proc_t* parent = pproc;
    
    // if there is no parent, then its parent is the kernel (hosting) proc
    if (parent == nil) parent = (proc_t*)hp;

    // lock the kernel process data stuctures
    lock(&hp->isched.l);

    // get it from the kernel
    nvp = new_vproc(parent, KPDUPPG | KPDUPFDG | KPDUPENVG);

    // release the process structures
    unlock(&hp->isched.l);

    return nvp;
}

/* Sys_spawn worker */
void
Sys_spawn(uv_work_t* workreq)
{

    vproc_t* newvp;

    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);

    hproc_t* hp = vp->hproc;

    // value if it fails
    sreq->spawn.ret = -1;

    if ((newvp = (vproc_t*)make_vproc((proc_t*)vp)) != nil) {
        sreq->spawn.ret = newvp->pid;
    }

}


void
Sys_pctl(uv_work_t* workreq)
{
    int fd, i;
	//List *l;
	Chan *c;
	//volatile struct {Pgrp *np;} np; */
	Pgrp *opg;
	Chan *dot;
	Osenv *o;
/*	F_Sys_pctl *f; */
	Fgrp *fg, *ofg, *nfg;
	/*volatile struct {Egrp *ne;} ne; */
	Egrp *oe;

    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);

	//if(sreq->pctl.flags & BlockingPctl)
	//	release();

	if(waserror()) {
		//closepgrp(np.np);
		//closeegrp(ne.ne);
		//if(f->flags & BlockingPctl)
		//	acquire();
		sreq->pctl.ret = -1;
		return;
	}

	o = vp->env;
	if(sreq->pctl.flags & Sys_NEWFD) {
		ofg = o->fgrp;
		nfg = newfgrp(ofg);
		lock(&ofg->l);
        int numfd = sreq->pctl.numfds;
		// file descriptors to preserve 
		for(i = 0; i < numfd; i++) {
			fd = sreq->pctl.movefd[i];
			if(fd >= 0 && fd <= ofg->maxfd) {
				c = ofg->fd[fd];
				if(c != nil && fd < nfg->nfd && nfg->fd[fd] == nil) {
					incref(&c->r);
					nfg->fd[fd] = c;
					if(nfg->maxfd < fd)
						nfg->maxfd = fd;
				}
			}
		}
		unlock(&ofg->l);
		o->fgrp = nfg;
		closefgrp(ofg);
	}
	else
	if(sreq->pctl.flags & Sys_FORKFD) {
		ofg = o->fgrp;
		fg = dupfgrp(ofg);
		// file descriptors to close
		for(i=0; i<sreq->pctl.numfds; i++)
			kclose(sreq->pctl.movefd[i]);
		o->fgrp = fg;
		closefgrp(ofg);
	}

/*	if(f->flags & Sys_NEWNS) {
		np.np = newpgrp();
		dot = o->pgrp->dot;
		np.np->dot = cclone(dot);
		np.np->slash = cclone(dot);
		cnameclose(np.np->slash->name);
		np.np->slash->name = newcname("/");
		np.np->nodevs = o->pgrp->nodevs;
		opg = o->pgrp;
		o->pgrp = np.np;
		np.np = nil;
		closepgrp(opg);
	}
	else
	if(f->flags & Sys_FORKNS) {
		np.np = newpgrp();
		pgrpcpy(np.np, o->pgrp);
		opg = o->pgrp;
		o->pgrp = np.np;
		np.np = nil;
		closepgrp(opg);
	}

	if(f->flags & Sys_NEWENV) {
		oe = o->egrp;
		o->egrp = newegrp();
		closeegrp(oe);
	}
	else
	if(f->flags & Sys_FORKENV) {
		ne.ne = newegrp();
		egrpcpy(ne.ne, o->egrp);
		oe = o->egrp;
		o->egrp = ne.ne;
		ne.ne = nil;
		closeegrp(oe);
	}

	if(f->flags & Sys_NEWPGRP)
		newgrp(p);

	if(f->flags & Sys_NODEVS)
		o->pgrp->nodevs = 1;
*/
	poperror();

//	if(f->flags & BlockingPctl)
//		acquire();

	sreq->pctl.ret = vp->pid;
}



/* dirread worker */
void
Sys_dirread(uv_work_t* workreq)
{
	Dir *b;
	int n;
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
    // configure a Dirpack return structure
    Dirpack* dp = (Dirpack*)malloc(sizeof(Dirpack));
    sreq->dirread.ret = dp;

    // default values
	dp->num = -1;
	dp->dirs = nil;
    
    
    // kernel call itself
	n = kdirread(sreq->dirread.fd->fd, &b);
      
    // if EOF or error
	if(n <= 0) {
        trace(TRACE_DEBUG, "node9: dirread worker, EOF with n=%d",n);
		dp->num = n;
		free(b);
	}
    else {    
        /* otherwise return the dirpack */
        dp->num = n;
        dp->dirs = b;
    }    
}

/*
void
Sys_fauth(void *fp)
{
	int fd;
	F_Sys_fauth *f;
	void *r;

	f = fp;
	r = *f->ret;
	*f->ret = H;
	destroy(r);
	release();
	fd = kfauth(fdchk(f->fd), string2c(f->aname));
	acquire();
	if(fd >= 0)
		*f->ret = mkfd(fd);
}

void
Sys_fversion(void *fp)
{
	void *r;
	F_Sys_fversion *f;
	int n;
	char buf[20], *s;

	f = fp;
	f->ret->t0 = -1;
	r = f->ret->t1;
	f->ret->t1 = H;
	destroy(r);
	s = string2c(f->version);
	n = strlen(s);
	if(n >= sizeof(buf)-1)
		n = sizeof(buf)-1;
	memmove(buf, s, n);
	buf[n] = 0;
	release();
	n = kfversion(fdchk(f->fd), f->msize, buf, sizeof(buf));
	acquire();
	if(n >= 0){
		f->ret->t0 = f->msize;
		retnstr(buf, n, &f->ret->t1);
	}
}
*/

void
Sys_iounit(uv_work_t* workreq)
{
    // get the syscall context
    vproc_t* vp = (vproc_t *) container_of(workreq, vproc_t, worker);
    N9SysReq* sreq = &(vp->sreq);
    // run as the caller
    uv_key_set(&prdakey, vp);
    
    
    sreq->iounit.ret = kiounit(fdchk(sreq->iounit.fd));    

}

/*
void
ccom(Progq **cl, Prog *p)
{
	volatile struct {Progq **cl;} vcl;

	cqadd(cl, p);
	vcl.cl = cl;
	if(waserror()) {
		if(p->ptr != nil) {	// no killcomm 
			cqdelp(vcl.cl, p);
			p->ptr = nil;
		}
		nexterror();
	}
	cblock(p);
	poperror();
}

void
crecv(Channel *c, void *ip)
{
	Prog *p;
	REG rsav;

	if(c->send->prog == nil && c->size == 0) {
		p = currun();
		p->ptr = ip;
		ccom(&c->recv, p);
		return;
	}

	rsav = R;
	R.s = &c;
	R.d = ip;
	irecv();
	R = rsav;
}

void
csend(Channel *c, void *ip)
{
 	Prog *p;
	REG rsav;

	if(c->recv->prog == nil && (c->buf == H || c->size == c->buf->len)) {
		p = currun();
		p->ptr = ip;
		ccom(&c->send, p);
		return;
	}

	rsav = R;
	R.s = ip;
	R.d = &c;
	isend();
	R = rsav;
}

int
csendalt(Channel *c, void *ip, Type *t, int len)
{
        REG rsav;

        if(c == H)
                error(exNilref);

        if(c->recv->prog == nil && (c->buf == H || c->size == c->buf->len)){
                if(c->buf != H){
                        print("csendalt failed\n");
                        freeptrs(ip, t);
                        return 0;
                }
                c->buf = H2D(Array*, heaparray(t, len));
        }

        rsav = R;
        R.s = ip;
        R.d = &c;
        isend();
        R = rsav;
        freeptrs(ip, t);
        return 1;
}

*/


/* Dispatcher Functions */

static uv_idle_t idle_watcher;

void
idler(uv_idle_t* idleinfo)
{
    /* place low-priority functions in here when necessary
    */
    trace(TRACE_DEBUG, "idling...");
}

void 
dispatch(uv_prepare_t* dispinfo)
{
    /* We are started before any other event collectors, so dispatch all active
     * requests to generate any relevant events
     */
    
    /* get the current hosting proc */
    hproc_t* hp = (hproc_t*) up;

    /* dispatch the system calls */  
    while (!QUEUE_EMPTY(&hp->reqq)) {
        /* get request from queue */
        QUEUE* q = QUEUE_HEAD(&hp->reqq);
        QUEUE_REMOVE(q);
        vproc_t* vp = QUEUE_DATA(q, vproc_t, node);
        
        /* either run the call directly or dispatch it as a worker thread */
        uv_queue_work(hp->loop, &vp->worker, vp->sreq.req.scall, worker_done);
        /* run the requested syscall directly */
        //(vp->req.scall)(vp);
        
    }


    /* at this point all required channel handles and watchers have been created
     * all blocking event generators are finished
     */
    
    /* if there are waiting vprocs or queued responses then
     * enable the idle watcher to prevent the loop from blocking
     *
     * the idler can also service certain low-priority functions
     */
    int empty = QUEUE_EMPTY(&hp->repq);
    
    if (waiting_procs || !empty) {
        uv_idle_start(&idle_watcher, idler);
        trace(TRACE_DEBUG, "idle bypass");
    }
    else {
        trace(TRACE_DEBUG, "no idle wait");
        uv_idle_stop(&idle_watcher);
    }
}

/* Buffer Management Functions */


#ifndef TRUE
#define TRUE 1
#endif
#ifndef FALSE
#define FALSE 0
#endif

#define DEFAULTALLOC 1024
#define ALLOCINCR 1024

int bbdebug = 1;

extern void* chkcalloc(size_t, size_t);
extern void* chkmalloc(size_t);
extern void* chkrealloc(void*,size_t);
extern void  chkfree(void*);

/* Following are always "in-lined"*/
#define bbLength(bb) ((bb)?(bb)->length:0U)
#define bbAlloc(bb) ((bb)?(bb)->alloc:0U)
#define bbContents(bb) ((bb && bb->content)?(bb)->content:(char*)"")
#define bbExtend(bb,len) bbSetalloc((bb),(len)+(bb->alloc))
#define bbClear(bb) ((void)((bb)?(bb)->length=0:0U))
#define bbNeed(bb,n) ((bb)?((bb)->alloc - (bb)->length) > (n):0U)
#define bbAvail(bb) ((bb)?((bb)->alloc - (bb)->length):0U)


/********* debug fns ***********/

void*
chkcalloc(size_t size, size_t nelems)
{
    return chkmalloc(size*nelems);
}

void*
chkmalloc(size_t size)
{
    void* memory = calloc(size,1); /* use calloc to zero memory*/
    if(memory == NULL) {
	panic("malloc:out of memory");
    }
    memset(memory,0,size);
    return memory;
}

void*
chkrealloc(void* ptr, size_t size)
{
    void* memory = realloc(ptr,size);
    if(memory == NULL) {
	panic("realloc:out of memory");
    }
    return memory;
}

void
chkfree(void* mem)
{
    if(mem != NULL) free(mem);
}

/********* debug fns ***********/

/* For debugging purposes*/
static long
bbFail(void)
{
    fflush(stdout);
    fprintf(stderr,"bytebuffer failure\n");
    fflush(stderr);
    if(bbdebug) exit(1);
    return FALSE;
}

Bytebuffer*
bbNew(void)
{
  Bytebuffer* bb = (Bytebuffer*)chkmalloc(sizeof(Bytebuffer));
  if(bb == NULL) return (Bytebuffer*)bbFail();
  bb->alloc=0;
  bb->length=0;
  bb->content=NULL;
  bb->nonextendible = 0;
  return bb;
}

int
bbSetalloc(Bytebuffer* bb, const unsigned int sz0)
{
  unsigned int sz = sz0;
  char* newcontent;
  if(bb == NULL) return bbFail();
  if(sz <= 0) {sz = (bb->alloc?2*bb->alloc:DEFAULTALLOC);}
  else if(bb->alloc >= sz) return TRUE;
  else if(bb->nonextendible) return bbFail();
  newcontent=(char*)chkcalloc(sz,sizeof(char));
  if(bb->alloc > 0 && bb->length > 0 && bb->content != NULL) {
    memcpy((void*)newcontent,(void*)bb->content,sizeof(char)*bb->length);
  }
  if(bb->content != NULL) chkfree(bb->content);
  bb->content=newcontent;
  bb->alloc=sz;
  return TRUE;
}

void
bbFree(Bytebuffer* bb)
{
  if(bb == NULL) return;
  if(bb->content != NULL) chkfree(bb->content);
  chkfree(bb);
}

int
bbSetlength(Bytebuffer* bb, const unsigned int sz)
{
  if(bb == NULL) return bbFail();
  if(bb->length < sz) {
      if(!bbSetalloc(bb,sz)) return bbFail();
  }
  bb->length = sz;
  return TRUE;
}

int
bbFill(Bytebuffer* bb, const char fill)
{
  unsigned int i;
  if(bb == NULL) return bbFail();
  for(i=0;i<bb->length;i++) bb->content[i] = fill;
  return TRUE;
}

int
bbGet(Bytebuffer* bb, unsigned int index)
{
  if(bb == NULL) return -1;
  if(index >= bb->length) return -1;
  return bb->content[index];
}

int
bbSet(Bytebuffer* bb, unsigned int index, char elem)
{
  if(bb == NULL) return bbFail();
  if(index >= bb->length) return bbFail();
  bb->content[index] = elem;
  return TRUE;
}

int
bbAppend(Bytebuffer* bb, char elem)
{
  if(bb == NULL) return bbFail();
  /* We need space for the char + null */
  while(bb->length+1 >= bb->alloc) {
    if(!bbSetalloc(bb,0))
      return bbFail();
  }
  bb->content[bb->length] = elem;
  bb->length++;
  bb->content[bb->length] = '\0';
  return TRUE;
}

/* This assumes s is a null terminated string*/
int
bbCat(Bytebuffer* bb, const char* s)
{
    bbAppendn(bb,(void*)s,strlen(s)+1); /* include trailing null*/
    /* back up over the trailing null*/
    if(bb->length == 0) return bbFail();
    bb->length--;
    return 1;
}

int
bbCatbuf(Bytebuffer* bb, const Bytebuffer* s)
{
    if(bbLength(s) > 0)
	bbAppendn(bb,bbContents(s),bbLength(s));
    bbNull(bb);
    return 1;
}

int
bbAppendn(Bytebuffer* bb, const void* elem, const unsigned int n0)
{
  unsigned int n = n0;
  if(bb == NULL || elem == NULL) return bbFail();
  if(n == 0) {n = strlen((char*)elem);}
  while(!bbNeed(bb,(n+1))) {if(!bbSetalloc(bb,0)) return bbFail();}
  memcpy((void*)&bb->content[bb->length],(void*)elem,n);
  bb->length += n;
  bb->content[bb->length] = '\0';
  return TRUE;
}

int
bbInsert(Bytebuffer* bb, const unsigned int index, const char elem)
{
  char tmp[2];
  tmp[0]=elem;
  return bbInsertn(bb,index,tmp,1);
}

int
bbInsertn(Bytebuffer* bb, const unsigned int index, const char* elem, const unsigned int n)
{
  unsigned int i;
  int j;
  unsigned int newlen = 0;

  if(bb == NULL) return bbFail();

  newlen = bb->length + n;

  if(newlen >= bb->alloc) {
    if(!bbExtend(bb,n)) return bbFail();
  }
  /*
index=0
n=3
len=3
newlen=6
a b c
x y z a b c
-----------
0 1 2 3 4 5

i=0 1 2
j=5 4 3
  2 1 0
*/
  for(j=newlen-1,i=index;i<bb->length;i++) {
    bb->content[j]=bb->content[j-n];
  }
  memcpy((void*)(bb->content+index),(void*)elem,n);
  bb->length += n;
  return TRUE;
}

/*! Pop head off of a byte buffer.
 *
 * @param Bytebuffer bb Pointer to Bytebuffer.
 * @param char* pelem pointer to location for head element.
 *
 * @return Returns TRUE on success.
 */
int bbHeadpop(Bytebuffer* bb, char* pelem)
{
  if(bb == NULL) return bbFail();
  if(bb->length == 0) return bbFail();
  *pelem = bb->content[0];
  memmove((void*)&bb->content[0],
          (void*)&bb->content[1],
          sizeof(char)*(bb->length - 1));
  bb->length--;
  return TRUE;
}

int
bbTailpop(Bytebuffer* bb, char* pelem)
{
  if(bb == NULL) return bbFail();
  if(bb->length == 0) return bbFail();
  *pelem = bb->content[bb->length-1];
  bb->length--;
  return TRUE;
}

int
bbHeadpeek(Bytebuffer* bb, char* pelem)
{
  if(bb == NULL) return bbFail();
  if(bb->length == 0) return bbFail();
  *pelem = bb->content[0];
  return TRUE;
}

int
bbTailpeek(Bytebuffer* bb, char* pelem)
{
  if(bb == NULL) return bbFail();
  if(bb->length == 0) return bbFail();
  *pelem = bb->content[bb->length - 1];
  return TRUE;
}

char*
bbDup(const Bytebuffer* bb)
{
    char* result = (char*)chkmalloc(bb->length+1);
    memcpy((void*)result,(const void*)bb->content,bb->length);
    result[bb->length] = '\0'; /* just in case it is a string*/
    return result;
}

int
bbSetcontents(Bytebuffer* bb, char* contents, const unsigned int alloc)
{
    if(bb == NULL) return bbFail();
    bbClear(bb);
    if(!bb->nonextendible && bb->content != NULL) chkfree(bb->content);
    bb->content = contents;
    bb->length = 0;
    bb->alloc = alloc;
    bb->nonextendible = 1;
    return 1;
}

/* Add invisible NULL terminator */
int
bbNull(Bytebuffer* bb)
{
    bbAppend(bb,'\0');
    bb->length--;
    return 1;
}

