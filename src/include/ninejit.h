ffi.cdef[[
/* Plan9 Specific Defs */

/* typedef uint16_t ushort */
typedef  int64_t vlong;
typedef	uint64_t uvlong;
typedef unsigned long ulong;

/* Resource Mgmt */
struct Ref
{
	Lock	lk;
	long	ref;
};

typedef struct FD FD;
struct FD
{
	Sys_FD	fd;
	Fgrp*	grp;
};


/* Process/Prog Definitions */
struct Proc
{
	int	type;		/* interpreter or not */
	char	text[KNAMELEN];
	Proc*	qnext;		/* list of processes waiting on a Qlock */
	long	pid;
	Proc*	next;		/* list of created processes */
	Proc*	prev;
	Lock	rlock;	/* sync between sleep/swiproc for r */
	Rendez*	r;		/* rendezvous point slept on */
	Rendez	sleep;		/* place to sleep */
	int		killed;		/* by swiproc */
	int	swipend;	/* software interrupt pending for Prog */
	int	syscall;	/* set true under sysio for interruptable syscalls */
	int	intwait;	/* spin wait for note to turn up */
	int	sigid;		/* handle used for signal/note/exception */
	Lock	sysio;		/* note handler lock */
	char	genbuf[128];	/* buffer used e.g. for last name element from namec */
	int	nerr;		/* error stack SP */
	osjmpbuf	estack[NERR];	/* vector of error jump labels */
	char*	kstack;
	void	(*func)(void*);	/* saved trampoline pointer for kproc */
	void*	arg;		/* arg for invoked kproc function */
	void*	iprog;		/* saved interp Prog during kernel calls (after release) */
	void*	prog;		/* saved native code Prog during kernel calls (after release) */
	Osenv*	env;		/* effective operating system environment */
	Osenv	defenv;		/* default env for slaves with no prog */
	osjmpbuf	privstack;	/* private stack for making new kids */
	osjmpbuf	sharestack;
	Proc	*kid;
	void	*kidsp;
	void	*os;		/* host os specific data */
};

/* this is a limbo channel, we'll have to call ours something else */
typedef struct Channel Channel;
struct Channel
{
/*        Array*  buf;    */        /* For buffered channels - must be first */
/*        Progq*  send;     */      /* Queue of progs ready to send */
/*        Progq*  recv;     */      /* Queue of progs ready to receive */
        void*   aux;                /* Rock for devsrv */
        void    (*mover)(void);     /* Data mover */
       /* union {
                WORD    w;
                Type*   t;
        } mid; */
        int     front;              /* Front of buffered queue */
        int     size;               /* Number of data items in buffered queue */
};

enum ProgState
{
        Palt,                           /* blocked in alt instruction */
        Psend,                          /* waiting to send */
        Precv,                          /* waiting to recv */
        Pdebug,                         /* debugged */
        Pready,                         /* ready to be scheduled */
        Prelease,                       /* interpreter released */
        Pexiting,                       /* exit because of kill or error */
        Pbroken,                        /* thread crashed */
};

enum
{
        /* Prog and Progs flags */
        Ppropagate = 1<<0,      /* propagate exceptions within group */
        Pnotifyleader = 1<<1,   /* send exceptions to group leader */
        Prestrict = 1<<2,       /* enforce memory limits */
        Prestricted = 1<<3,
        Pkilled = 1<<4,
        Pprivatemem = 1<<5      /* keep heap and stack private */
};

typedef struct Progs    Progs;
typedef struct Prog     Prog;

struct Progs
{
        int     id;
        int     flags;
        Progs*  parent;
        Progs*  child;
        Progs*  sib;
        Prog*   head;   /* live group leader is at head */
        Prog*   tail;
};


struct Prog
{
        /* the first entry here will eventually be the lua state */
        //Prog*           link;         /* Run queue */
        Channel*        chan;           /* Channel pointer - not same as Chan */
        void*           ptr;            /* Channel data pointer */
        enum ProgState  state;          /* Scheduler state (shadow of luvL scheduler state? */
        char*           kill;           /* Set if prog should error */
        char*           killstr;        /* kill string buffer when needed */
        int             pid;            /* unique Prog id */
        int             quanta;         /* time slice */
        ulong           ticks;          /* time used */
        int             flags;          /* error recovery flags */
        /* unlikely these will be needed in future as 
         * luv handles sheduling
         */
        Prog*           prev;
        Prog*           next;
        Prog*           pidlink;        /* next in pid hash chain */
        /* needed to properly model pgrp internally */
        Progs*          group;          /* process group */
        Prog*           grpprev;        /* previous group member */
        Prog*           grpnext;        /* next group member */
        /* unknown how much we'll need this */
        void*           exval;          /* current exception */
        char*           exstr;          /* last exception */
        /* these are copied from the parent by newprog */
        void*           osenv;
        void*           context;        /* virtual machine task context */
};

/*
 *  synchronization
 */
typedef
struct Lock {
        int     val;
        int     pid;
} Lock;

extern int      _tas(int*);

extern  void    lock(Lock*);
extern  void    unlock(Lock*);
extern  int     canlock(Lock*);

typedef struct QLock QLock;
struct QLock
{
        Lock    use;                    /* to access Qlock structure */
        Proc    *head;                  /* next process waiting for object */
        Proc    *tail;                  /* last process waiting for object */
        int     locked;                 /* flag */
};

extern  void    qlock(QLock*);
extern  void    qunlock(QLock*);
extern  int     canqlock(QLock*);
extern  void    _qlockinit(ulong (*)(ulong, ulong));    /* called only by the thread library */

typedef
struct RWLock
{
        Lock    l;                      /* Lock modify lock */
        QLock   x;                      /* Mutual exclusion lock */
        QLock   k;                      /* Lock for waiting writers */
        int     readers;                /* Count of readers in lock */
} RWLock;

extern  int     canrlock(RWLock*);
extern  int     canwlock(RWLock*);
extern  void    rlock(RWLock*);
extern  void    runlock(RWLock*);
extern  void    wlock(RWLock*);
extern  void    wunlock(RWLock*);

/* kernel device access and channels */

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
/*rsc	CCREATE	= 0x0004,		/* permits creation if c->mnt */
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

/* channel name */

struct Cname
{
	Ref	r;
	int	alen;			/* allocated length */
	int	len;			/* strlen(s) */
	char	*s;
};



]]
