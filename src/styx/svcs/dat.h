#ifndef DAT_H
#define DAT_H

typedef struct Block	Block;
typedef struct Chan	Chan;
typedef struct Cmdbuf	Cmdbuf;
typedef struct Cmdtab	Cmdtab;
typedef struct Cname	Cname;
typedef struct Dev	Dev;
typedef struct Dirtab	Dirtab;
typedef struct Egrp	Egrp;
typedef struct Evalue	Evalue;
typedef struct Fgrp	Fgrp;
typedef struct Mount	Mount;
typedef struct Mntcache Mntcache;
typedef struct Mntparam Mntparam;
typedef struct Mntrpc	Mntrpc;
typedef struct Mntwalk	Mntwalk;
typedef struct Mnt	Mnt;
typedef struct Mhead	Mhead;
typedef struct Osenv	Osenv;
typedef struct Pgrp	Pgrp;
//typedef struct Proc	Proc;
typedef struct Queue	Queue;
typedef struct Rendez Rendez;
typedef struct Ref	Ref;
typedef struct Rootdata Rootdata;
/*typedef struct RWlock	RWlock;*/
typedef struct RWLock	RWlock;
typedef struct Procs	Procs;
typedef struct Signerkey Signerkey;
typedef struct Skeyset	Skeyset;
typedef struct Uqid	Uqid;
typedef struct Uqidtab	Uqidtab;
typedef struct Walkqid	Walkqid;

typedef struct Progq Progq;
typedef struct Channel Channel;
typedef struct KProc kproc_t;       /* slave kernel process */
typedef struct Proc  proc_t;        /* generic kernel process */ 
typedef struct VProc vproc_t;       /* interpreter (vm) process */
typedef struct HProc hproc_t;       /* hosting proc: kproc that hosts vm procs */

extern char* eve;

#include "lib9.h"
#undef CHDIR
#undef NAMELEN
#undef ERRLEN

#include "emu.h"

#pragma incomplete Queue
#pragma incomplete Mntrpc

#define container_of(ptr, type, member) \
  ((type*) ((char*)(ptr) - offsetof(type, member)))

#include "interp.h"
#include "fcall.h"
#include "pool.h"

typedef int    Devgen(Chan*, char*, Dirtab*, int, int, Dir*);

enum
{
	NERR		= 32,
	KNAMELEN	= 28,
	MAXROOT		= 5*KNAMELEN, 	/* Maximum root pathname len of devfs-* */
	NUMSIZE		= 11,
	PRINTSIZE	= 256,
	READSTR		= 1000		/* temporary buffer size for device reads */
};

struct Ref
{
	Lock	lk;
	long	ref;
};

struct Rendez
{
	Lock	l;
	kproc_t*	p;
};

/*
struct Rept
{
	Lock	l;
	Rendez	r;
	void	*o;
	int	t;
	int	(*active)(void*);
	int	(*ck)(void*, int);
	void	(*f)(void*); 
}; */

/*
 * Access types in namec & channel flags
 */
enum
{
	Aaccess,			/* as in access, stat */
	Abind,			/* for left-hand-side of bind */
	Atodir,				/* as in chdir */
	Aopen,				/* for i/o */
	Amount,				/* to be mounted upon */
	Acreate,			/* file is to be created */
	Aremove,			/* will be removed by caller */

	COPEN	= 0x0001,		/* for i/o */
	CMSG	= 0x0002,		/* the message channel for a mount */
//rsc	CCREATE	= 0x0004,		/* permits creation if c->mnt */
	CCEXEC	= 0x0008,		/* close on exec */
	CFREE	= 0x0010,		/* not in use */
	CRCLOSE	= 0x0020,		/* remove on close */
	CCACHE	= 0x0080		/* client cache */
};

struct Chan
{
	Lock	l;
	Ref	r;
	Chan*	next;			/* allocation */
	Chan*	link;
	vlong	offset;			/* in file */
	ushort	type;
	ulong	dev;
	ushort	mode;			/* read/write */
	ushort	flag;
	Qid	qid;
	int	fid;			/* for devmnt */
	ulong	iounit;	/* chunk size for i/o; 0==default */
	Mhead*	umh;			/* mount point that derived Chan; used in unionread */
	Chan*	umc;			/* channel in union; held for union read */
	QLock	umqlock;		/* serialize unionreads */
	int	uri;			/* union read index */
	int	dri;			/* devdirread index */
	ulong	mountid;
	Mntcache *mcp;			/* Mount cache pointer */
	Mnt		*mux;		/* Mnt for clients using me for messages */
	void*	aux;		/* device specific data */
	Chan*	mchan;			/* channel to mounted server */
	Qid	mqid;			/* qid of root of mount point */
	Cname	*name;
};

struct Cname
{
	Ref	r;
	int	alen;			/* allocated length */
	int	len;			/* strlen(s) */
	char	*s;
};

struct Dev
{
    int     dc;
    char*   name;

    void        (*init)();
    Chan*       (*attach)(char*);
    Walkqid*    (*walk)(Chan*, Chan*, char**, int);
    int         (*stat)(Chan*, uchar*, int);
    Chan*       (*open)(Chan*, int);
    void        (*create)(Chan*, char*, int, ulong);
    void        (*close)(Chan*);
    long        (*read)(Chan*, void*, long, vlong);
    Block*      (*bread)(Chan*, long, ulong);
    long        (*write)(Chan*, void*, long, vlong);
    long        (*bwrite)(Chan*, Block*, ulong);
    void        (*remove)(Chan*);
    int         (*wstat)(Chan*, uchar*, int);
};

enum
{
	BINTR		=	(1<<0),
	BFREE		=	(1<<1),
	BMORE		=	(1<<2)		/* continued in next block */
};

struct Block
{
	Block*	next;
	Block*	list;
	uchar*	rp;			/* first unconsumed byte */
	uchar*	wp;			/* first empty byte */
	uchar*	lim;			/* 1 past the end of the buffer */
	uchar*	base;			/* start of the buffer */
	void	(*free)(Block*);
	ulong	flag;
};
#define BLEN(s)	((s)->wp - (s)->rp)
#define BALLOC(s) ((s)->lim - (s)->base)

struct Dirtab
{
	char	name[KNAMELEN];
	Qid	qid;
	vlong	length;
	long	perm;
};

struct Walkqid
{
	Chan	*clone;
	int	nqid;
	Qid	qid[1];
};

enum
{
	NSMAX	=	1000,
	NSLOG	=	7,
	NSCACHE	=	(1<<NSLOG)
};

struct Mntwalk				/* state for /proc/#/ns */
{
	int		cddone;
	ulong	id;
	Mhead*	mh;
	Mount*	cm;
};

struct Mount
{
	ulong	mountid;
	Mount*	next;
	Mhead*	head;
	Mount*	copy;
	Mount*	order;
	Chan*	to;			/* channel replacing channel */
	int	mflag;
	char	*spec;
};

struct Mhead
{
	Ref	r;
	RWlock	lock;
	Chan*	from;			/* channel mounted upon */
	Mount*	mount;			/* what's mounted upon it */
	Mhead*	hash;			/* Hash chain */
};

struct Mnt
{
	Lock	l;
	/* references are counted using c->ref; channels on this mount point incref(c->mchan) == Mnt.c */
	Chan*	c;		/* Channel to file service */
	proc_t*	rip;		/* Reader in progress */
	Mntrpc*	queue;		/* Queue of pending requests on this channel */
	ulong	id;		/* Multiplexor id for channel check */
	Mnt*	list;		/* Free list */
	int	flags;		/* cache */
	int	msize;		/* data + IOHDRSZ */
	char	*version;			/* 9P version */
	Queue	*q;		/* input queue */
};

enum
{
	MNTLOG	=	5,
	MNTHASH =	1<<MNTLOG,		/* Hash to walk mount table */
	DELTAFD=		20,		/* allocation quantum for process file descriptors */
	MAXNFD =		4000,		/* max per process file descriptors */
	MAXKEY =		8	/* keys for signed modules */
};
#define MOUNTH(p,qid)	((p)->mnthash[(qid).path&((1<<MNTLOG)-1)])

struct Mntparam {
	Chan*	chan;
	Chan*	authchan;
	char*	spec;
	int	flags;
};

/* process group and namespace */
struct Pgrp
{
	Ref	    r;			/* also used as a lock when mounting */
	ulong	pgrpid;
	RWlock	ns;			/* Namespace n read/one write lock */
	QLock	nsh;
	Mhead*	mnthash[MNTHASH];
	int	    progmode;
	Chan*	dot;
	Chan*	slash;
	int	    nodevs;
	int	    pin;
};

enum
{
	Nopin =	-1
};

struct Fgrp
{
	Lock	l;
	Ref	r;
	Chan**	fd;
	int	nfd;			/* number of fd slots */
	int	maxfd;			/* highest fd in use */
	int	minfd;			/* lower bound on free fd */
};

struct Evalue
{
	char	*var;
	char	*val;
	int	len;
	Qid	qid;
	Evalue	*next;
};

struct Egrp
{
	Ref	r;
	QLock	l;
	ulong	path;
	ulong	vers;
	Evalue	*entries;
};

struct Signerkey
{
	Ref	r;
	char*	owner;
	ushort	footprint;
	ulong	expires;
	void*	alg;
	void*	pk;
	void	(*pkfree)(void*);
};

struct Skeyset
{
	Ref	r;
	QLock	l;
	ulong	flags;
	char*	devs;
	int	nkey;
	Signerkey	*keys[MAXKEY];
};

struct Uqid
{
	Ref	r;
	int	type;
	int	dev;
	vlong	oldpath;
	vlong	newpath;
	Uqid*	next;
};

enum
{
	Nqidhash = 32
};

struct Uqidtab
{
	QLock	l;
	Uqid*	qids[Nqidhash];
	ulong	pathgen;
};

struct Osenv
{
	char        *syserrstr;         /* last error from a system call, errbuf0 or 1 */
	char        *errstr;            /* reason we're unwinding the error stack, errbuf1 or 0 */
	char        errbuf0[ERRMAX];
	char        errbuf1[ERRMAX];
	Pgrp*       pgrp;               /* Ref to namespace, working dir and root */
	Fgrp*       fgrp;               /* Ref to file descriptors */
	Egrp*       egrp;               /* Environment vars */
	Skeyset*    sigs;               /* Signed module keys */
	Queue*      waitq;              /* procs interested in exit status */
	Queue*      childq;             /* list of children waiting */
	void*       debug;              /* Debugging master */
	char*       user;               /* Inferno user name */
	int	        uid;                /* Numeric user id for host system */
	int	        gid;                /* Numeric group id for host system */
	void        *ui;                /* User info for NT */
};

enum
{
	Unknown	= 0xdeadbabe,
	IdleGC	= 0x16,
	Interp	= 0x17,
	BusyGC	= 0x18,
	Moribund
};

struct Channel
{
	//Array*	buf;		/* For buffered channels - must be first */
	Progq*	send;		/* Queue of progs ready to send */
	Progq*	recv;		/* Queue of progs ready to receive */
	void*	aux;		/* Rock for devsrv */
	void	(*mover)(void);	/* Data mover */
	//union //{
	//	WORD	w;
	//	Type*	t;
	//} mid;
	int	front;	/* Front of buffered queue */
	int	size;		/* Number of data items in buffered queue */
};

enum ProcType
{
    Kern_proc,
    Host_proc,
    Vm_proc
};


/* default process fields required to support namespace,
 * file groups, environment groups, process id, paths
 * and error recovery.  these are the minimum fields required
 * to support process control, interaction and system calls.
 */
#define PROC_BASE_FIELDS \
    enum ProcType   ptype;            /* process type: kproc, hproc or vm proc */ \
    hproc_t*        hproc;            /* kernel proc that's hosting this proc */ \
    char            text[KNAMELEN];   /* proc name */   \
    long            pid;              /* proc id */     \
    Osenv*          env;              /* os environ */  \
    Osenv           defenv;           /* default env buffer area */ \
    char            genbuf[128];      /* path buffer */ \
    int             nerr;             /* error depth */ \
    osjmpbuf        estack[NERR];     /* error stack */ \
    proc_t*         qnext;            /* procs waiting in line */ \
    int             syscall;          /* true during cmd call to host os */ \
    /* baton support */ \
    void*       data

#define KERN_BASE_FIELDS \
    Lock            rlock;            /* sync between sleep/swiproc for r */ \
    char*           kstack;           /* custom stack at launch */ \
    int             killed;           /* has the proc been killed? */ \
    int             swipend;          /* software interrupt pending */ \
    int             intwait;          /* waiting for a note to be posted */ \
    Lock            sysio;            /* lock for notifications */ \
    Rendez*         r;                /* rendezvous for this process */ \
    kproc_t*        prev;             /* the previous kproc */ \
    kproc_t*        next;             /* the next kproc */ \
    Dirtab*         roottab;          /* the directory entries in the root directory file */ \
    Rootdata*       rootdata;         /* the in-memory file contents of the root device: files/dirs etc */ \
    void            (*func)(void*);   /* startup function */ \
    void*           arg;              /* startup argument */ \
    /* os / implementation dependent fields */ \
    Osdep*          os          

/* generic process, can be either a kernel or interpreter process */
struct Proc
{
	PROC_BASE_FIELDS;
};

/* kernel process is a libuv thread which can have it's own device
 * table or share one with it's parent kproc.
 */
struct KProc
{
    PROC_BASE_FIELDS;
    KERN_BASE_FIELDS;
};

/* kernel userland hosting process:  A variation of a kproc,
 * the hproc, hosts a luajit virtual machine for user processes.
 */
struct HProc
{
    PROC_BASE_FIELDS;
    KERN_BASE_FIELDS;
    uv_loop_t*      loop;           /* i/o event loop pointer (promoted here because its used constantly) */ \
    uv_async_t      ev_wake;        /* generic event loop wakeup on stall or external event */ \
    vproc_t*        rootproc;       /* the root user/lua proc (usually 'init') */
    int             pidnum;         /* last assigned interpreter pid */
    sched_t         isched;         /* vproc list (syncs or shadows luv states */          
    vproc_t*        proghash[64];   /* quick lookup table for intepreter procs */
    QUEUE           reqq;           /* kernel syscall request queue */
    QUEUE           repq;           /* kernel syscall reply queue */
};

/* VProc is the kernel state of a VM fiber (coroutine).  Everyone gets a basic proc
 * structure, even VM fibers.  VM syscalls are executed in the context of
 * of the calling fiber which is only possible because each fiber has it's own process.
 * (This is implemented by setting the "current process" thread-local-storage "up" 
 * value in the userspace thread worker to that of the vproc)
 */
struct VProc {
    PROC_BASE_FIELDS;
	Channel*        chan;           /* Channel pointer */
	void*           ptr;            /* Channel data pointer */
    enum ProgState  state;          /* vproc_t state, synced /w luv state */
    char*           kill;           /* kill state */
    char*           killstr;        /* kill string */
    int             quanta;         /* ticks per slice */
    int             ticks;          /* current tick count (quanta remaining) */
    int             flags;          /* group / prop flags */
    vproc_t*        prev;           /* prev proc in list */
    vproc_t*        next;           /* next proc in list */
    vproc_t*        pidlink;        /* next in pid hash table */
    Progs*          group;          /* proc group to which vproc belongs */
    vproc_t*        grpprev;        /* previous group member */
    vproc_t*        grpnext;        /* next group member */
    void*           exval;          /* exception val ptr */
    char*           exstr;          /* last exception string */
    QUEUE           node;           /* vprocs place in request/reply queue */
    uv_async_t      swi_wake;       /* wake handle to hosting event loop */
    uv_work_t       worker;         /* libuv worker interface */
    uv_timer_t      ticker;         /* libuv timer interface */
    N9SysReq        sreq;           /* the vproc's sysreq buffer */
};


struct Progq
{
	vproc_t*    prog;
	Progq*      next;
};


#define poperror()	up->nerr--
#define waserror()	(up->nerr++, ossetjmp(up->estack[up->nerr-1]))

enum
{
	/* kproc flags */
	KPDUPPG		= (1<<0),
	KPDUPFDG	= (1<<1),
	KPDUPENVG	= (1<<2),
	KPX11		= (1<<8),		/* needs silly amount of stack */
	KPDUP		= (KPDUPPG|KPDUPFDG|KPDUPENVG)
};

struct Procs
{
	Lock	    l;
	kproc_t*	head;
	kproc_t*	tail;
};

struct Rootdata
{
	int	    dotdot;
	void	*ptr;
	int	    size;
	int	    *sizep;
};

extern	char	*ossysname;
extern	Queue*	kbdq;
extern	Queue*	gkbdq;
extern	Queue*	gkscanq;
extern	int	Xsize;
extern	int	Ysize;
extern	Pool*	mainmem;
extern	char	rootdir[MAXROOT];		/* inferno root */
extern	Procs	procs;
extern	int	sflag;
extern	int	xtblbit;
extern	int	globfs;
extern	int	greyscale;
extern	uint	qiomaxatomic;


struct Cmdbuf
{
	char	*buf;
	char	**f;
	int	nf;
};

struct Cmdtab
{
	int	index;	/* used by client to switch on result */
	char	*cmd;	/* command name */
	int	narg;	/* expected #args; 0 ==> variadic */
};

/* queue state bits,  Qmsg, Qcoalesce, and Qkick can be set in qopen */
enum
{
	/* Queue.state */
	Qstarve		= (1<<0),	/* consumer starved */
	Qmsg		= (1<<1),	/* message stream */
	Qclosed		= (1<<2),	/* queue has been closed/hungup */
	Qflow		= (1<<3),	/* producer flow controlled */
	Qcoalesce	= (1<<4),	/* coallesce packets on read */
	Qkick		= (1<<5),	/* always call the kick routine after qwrite */
};

#define DEVDOTDOT -1

#pragma varargck	type	"I" uchar*
#pragma	varargck	type	"E" uchar*

extern void	(*mainmonitor)(int, void*, ulong);

#endif
