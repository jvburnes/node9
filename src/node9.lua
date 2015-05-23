-- first load the architecture info library
--require('nodearch')
--arch = ffi.load("arch")

-- now compute the machine-dependent types
ffi.cdef("typedef int osjmpbuf[" .. arch.jumpsize() .. "]")

-- load the full kernel interface, this will eventually be mediated through
-- ffi.load("node9")

ffi.cdef[[
/* Plan9/Inferno Specific Structures */

/* NOTE: libarch must be loaded before this, so proper structure sizes can be
 * determined 
 */
 
/* typedef uint16_t ushort */
typedef  int64_t vlong;
typedef	uint64_t uvlong;
typedef unsigned long ulong;
typedef unsigned short ushort;
typedef unsigned char uchar;
typedef unsigned int uint;

/* structure types */
typedef struct Lock Lock;
typedef struct Ref Ref;
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
typedef struct Proc	Proc;
typedef struct Queue	Queue;
typedef struct Ref	Ref;
typedef struct Rept	Rept;
typedef struct RWLock	RWlock;
typedef struct Procs	Procs;
typedef struct Signerkey Signerkey;
typedef struct Skeyset	Skeyset;
typedef struct Uqid	Uqid;
typedef struct Uqidtab	Uqidtab;
typedef struct Walkqid	Walkqid;
typedef struct Osenv Osenv;

/* Err Enums / Consts */

enum
{
    ERRMAX	= 128	/* max length of error string */
};

/* Kernel Defs */

enum
{
	NERR		= 32,
	KNAMELEN	= 28,
	MAXROOT		= 5*KNAMELEN, 	/* Maximum root pathname len of devfs-* */
	NUMSIZE		= 11,
	PRINTSIZE	= 256,
	READSTR		= 1000		    /* temporary buffer size for device reads */
};

enum
{
	MORDER	= 0x0003,	/* mask for bits defining order of mounting */
	MREPL	= 0x0000,	/* mount replaces object */
	MBEFORE	= 0x0001,	/* mount goes before others in union directory */
	MAFTER	= 0x0002,	/* mount goes after others in union directory */
	MCREATE	= 0x0004,	/* permit creation in mounted directory */
	MCACHE	= 0x0010,	/* cache some data */
	MMASK	= 0x0017	/* all bits on */
};

enum
{
	OREAD	= 0,	/* open for read */
	OWRITE	= 1,	/* write */
	ORDWR	= 2,	/* read and write */
	OEXEC	= 3,	/* execute, == read but check execute permission */
	OTRUNC	= 16,	/* or'ed in (except for exec), truncate file first */
	OCEXEC	= 32,	/* or'ed in, close on exec */
	ORCLOSE	= 64,	/* or'ed in, remove on close */
	OEXCL	= 0x1000	/* or'ed in, exclusive use (create only) */
};

enum
{
	AEXIST	= 0,	/* accessible: exists */
	AEXEC	= 1,	/* execute access */
	AWRITE	= 2,	/* write access */
	AREAD	= 4	/* read access */
};

enum
{
/* bits in Qid.type */
    QTDIR    = 0x80,		/* type bit for directories */
    QTAPPEND = 0x40,		/* type bit for append only files */
    QTEXCL   = 0x20,		/* type bit for exclusive use files */
    QTMOUNT  = 0x10,		/* type bit for mounted channel */
    QTAUTH   = 0x08,		/* type bit for authentication file */
    QTFILE   = 0x00		/* plain file */
};

enum
{
/* bits in Dir.mode */
    DMDIR    = 0x80000000,      /* mode bit for directories */
    DMAPPEND = 0x40000000,      /* mode bit for append only files */
    DMEXCL   = 0x20000000,      /* mode bit for exclusive use files */
    DMMOUNT  = 0x10000000,      /* mode bit for mounted channel */
    DMAUTH   = 0x08000000,      /* mode bit for authentication file */
    DMREAD   = 0x4,             /* mode bit for read permission */
    DMWRITE  = 0x2,             /* mode bit for write permission */
    DMEXEC   = 0x1             /* mode bit for execute permission */
};

/*
 *  synchronization
 */
typedef
struct Lock {
        int     val;
        int     pid;
} Lock;


/* Process/Prog Definitions */

struct Osenv
{
	char	*syserrstr;	/* last error from a system call, errbuf0 or 1 */
	char	*errstr;	/* reason we're unwinding the error stack, errbuf1 or 0 */
	char	errbuf0[ERRMAX];
	char	errbuf1[ERRMAX];
	Pgrp*	pgrp;		/* Ref to namespace, working dir and root */
	Fgrp*	fgrp;		/* Ref to file descriptors */
	Egrp*	egrp;	/* Environment vars */
	Skeyset*		sigs;		/* Signed module keys */
	Queue*	waitq;		/* Info about dead children */
	Queue*	childq;		/* Info about children for debuggers */
	void*	debug;		/* Debugging master */
	char*	user;	/* Inferno user name */
	int	uid;		/* Numeric user id for host system */
	int	gid;		/* Numeric group id for host system */
	void	*ui;		/* User info for NT */
};


struct Proc
{
	int	type;		/* interpreter or not */
    char	text[KNAMELEN];
	Proc*	qnext;		/* list of processes waiting on a Qlock */
	long	pid;
	Proc*	next;		/* list of created processes */
	Proc*	prev;
	Lock	rlock;	/* sync between sleep/swiproc for r */
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

struct Procs
{
	Lock	l;
	Proc*	head;
	Proc*	tail;
};

/* this is a limbo channel.  luajit can use the same structure, slightly modified */ 
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

/* we'll have to match these states to the luv states */

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

/* these should work as long as we modify pctl */

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

/* likely not needed as luv tracks these */

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

/* this maps to a node9 fiber.  probably won't need prev/next as 
 * luv tracks it's own fibers and these simply shadow them
 *
 */
 
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

/* Resource Mgmt */

struct Ref
{
	Lock	lk;
	long	ref;
};


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


typedef
struct Qid
{
	uvlong	path;
	ulong	vers;
	uchar	type;
} Qid;

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
	int	fid;			    /* for devmnt */
	ulong	iounit;	        /* chunk size for i/o; 0==default */
	Mhead*	umh;			/* mount point that derived Chan; used in unionread */
	Chan*	umc;			/* channel in union; held for union read */
	QLock	umqlock;		/* serialize unionreads */
	int	uri;			    /* union read index */
	int	dri;			    /* devdirread index */
	ulong	mountid;
	Mntcache *mcp;			/* Mount cache pointer */
	Mnt		*mux;		    /* Mnt for clients using me for messages */
	void*	aux;		    /* device specific data */
	Chan*	mchan;			/* channel to mounted server */
	Qid	mqid;		    	/* qid of root of mount point */
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

/* Namespace, process groups etc */


struct Dev
{
	int	dc;
	char*	name;

	void	(*init)(void);
	Chan*	(*attach)(char*);
	Walkqid*	(*walk)(Chan*, Chan*, char**, int);
	int	(*stat)(Chan*, uchar*, int);
	Chan*	(*open)(Chan*, int);
	void	(*create)(Chan*, char*, int, ulong);
	void	(*close)(Chan*);
	long	(*read)(Chan*, void*, long, vlong);
	Block*	(*bread)(Chan*, long, ulong);
	long	(*write)(Chan*, void*, long, vlong);
	long	(*bwrite)(Chan*, Block*, ulong);
	void	(*remove)(Chan*);
	int	(*wstat)(Chan*, uchar*, int);
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
	Proc*	rip;		/* Reader in progress */
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

struct Mntparam {
	Chan*	chan;
	Chan*	authchan;
	char*	spec;
	int	flags;
};

struct Pgrp
{
	Ref	r;			/* also used as a lock when mounting */
	ulong	pgrpid;
	RWlock	ns;			/* Namespace n read/one write lock */
	QLock	nsh;
	Mhead*	mnthash[MNTHASH];
	int	progmode;
	Chan*	dot;
	Chan*	slash;
	int	nodevs;
	int	pin;
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


typedef 
struct Dir {
	/* system-modified data */
	ushort	type;	/* server type */
	uint	dev;	/* server subtype */
	/* file data */
	Qid	qid;	/* unique id from server */
	ulong	mode;	/* permissions */
	ulong	atime;	/* last read time */
	ulong	mtime;	/* last write time */
	vlong	length;	/* file length */
	char	*name;	/* last element of path */
	char	*uid;	/* owner name */
	char	*gid;	/* group name */
	char	*muid;	/* last modifier name */
} Dir;

enum {
    STATMAX	= 65535U,	/* max length of machine-independent stat structure */
    DIRMAX	= (sizeof(Dir)+STATMAX),	/* max length of Dir structure */
};


]]
