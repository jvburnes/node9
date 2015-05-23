/* Sys Request Interace */


/* Sys Request Structures */
typedef struct N9Req         N9Req;
typedef struct N9SysOpen     N9SysOpen;
typedef struct N9SysCreate   N9SysCreate;
typedef struct N9SysDup      N9SysDup;
typedef struct N9SysFildes   N9SysFildes;
typedef struct N9SysSeek     N9SysSeek;
typedef struct N9SysIounit   N9SysIounit;
typedef struct N9SysRead     N9SysRead;
typedef struct N9SysReadn    N9SysReadn;
typedef struct N9SysPread    N9SysPread;
typedef struct N9SysPrint    N9SysPrint;
typedef struct N9SysFprint   N9SysFprint;
typedef struct N9SysWrite    N9SysWrite;
typedef struct N9SysPwrite   N9SysPwrite;
typedef struct N9SysStat     N9SysStat;
typedef struct N9SysFstat    N9SysFstat;
typedef struct N9SysWstat    N9SysWstat;
typedef struct N9SysFwstat   N9SysFwstat;
typedef struct N9SysRemove   N9SysRemove;
typedef struct N9SysChdir    N9SysChdir;
typedef struct N9SysFd2path  N9SysFd2path;
typedef struct N9SysDial     N9SysDial;
typedef struct N9SysAnnounce N9SysAnnounce;
typedef struct N9SysListen   N9SysListen;
typedef struct N9SysBind     N9SysBind;
typedef struct N9SysMount    N9SysMount;
typedef struct N9SysUnmount  N9SysUnmount;
typedef struct N9SysExport   N9SysExport;
typedef struct N9SysSpawn    N9SysSpawn;
typedef struct N9SysPctl     N9SysPctl;
typedef struct N9SysDirread  N9SysDirread;
typedef struct N9SysSleep    N9SysSleep;
typedef struct N9FreeFD      N9FreeFD;
typedef union  N9SysReq      N9SysReq;

/* header structure */
struct N9Req 
{
    void*           proc;
    void            (*scall)(void *);
};

/* request packets */
struct N9SysOpen
{
    N9Req           req;
    Sys_FD*         ret;
    char*           s;
    int             mode;
};

struct N9SysCreate
{
    N9Req           req;
    Sys_FD*         ret;
    char*           s;
    int             mode;
    int             perm;
};

struct N9SysFildes
{
	N9Req           req;
	Sys_FD*         ret;
	int             fd;
};

struct N9SysIounit
{
    N9Req           req;
    int             ret;
    Sys_FD*         fd;
};


struct N9SysRead
{
    N9Req           req;
    int             ret;
    Sys_FD*         fd;
    Bytebuffer*     buf;
    int             nbytes;
};

struct N9FreeFD
{
    N9Req           req;
    Sys_FD*         fd;
};

struct N9SysSeek
{
	N9Req           req;
	int64_t         ret;
	Sys_FD*	        fd;
	int64_t         off;
	int             start;
};

struct N9SysDup
{
	N9Req           req;
    int             ret;
	int             old;
    int             new;
};

struct N9SysReadn
{
    N9Req           req;
    int             ret;
    Sys_FD*         fd;
    Bytebuffer*     buf;
    int             n;
};

struct N9SysPread
{
    N9Req           req;
    int             ret;
    Sys_FD*         fd;
    Bytebuffer*     buf;
    int             n;
	int64_t         off;
};

struct N9SysDirread
{
    N9Req           req;
    Dirpack*        ret;
    Sys_FD*         fd;
};

struct N9SysWrite
{
    N9Req           req;
    int             ret;
    Sys_FD*         fd;
    Bytebuffer*     buf;
    int             nbytes;
};

struct N9SysPwrite
{
	N9Req           req;
	int             ret;
	Sys_FD*         fd;
	Bytebuffer*     buf;
	int             n;
    int64_t         off;
};

struct N9SysPrint
{
    N9Req           req;
    int             ret;
    const char*     buf;
    int             len;
};

struct N9SysFprint
{
    N9Req           req;
    int             ret;
    Sys_FD*         fd;
    const char*     buf;
    int             len;
};

struct N9SysStat
{
	N9Req           req;
	Dir*            ret;
    char*           s;
};

struct N9SysFstat
{
	N9Req           req;
	Dir*            ret;
    Sys_FD*         fd;
};

struct N9SysWstat
{
	N9Req           req;
	int             ret;
    char*           s;
    Dir*            dir;
};

struct N9SysFwstat
{
	N9Req           req;
	int             ret;
    Sys_FD*         fd;
    Dir*            dir;
};


struct N9SysBind
{
    N9Req           req;
    int             ret;
    char*           name;
    char*           on;
    int             flags;
};

struct N9SysMount
{
	N9Req           req;
    int             ret;
    Sys_FD*         fd;
    Sys_FD*         afd;
    char*           on;
    int             flags;
    char*           spec;
};

struct N9SysUnmount
{
    N9Req           req;
    int             ret;
    char*           name;
    char*           from;
};

struct N9SysRemove
{
	int         ret;
	char*       s;
};

struct N9SysChdir
{
	int         ret;
	char*       path;
};

struct N9SysFd2path
{
	char*       ret;
	Sys_FD*     fd;
};

/*
void Sys_file2chan(void*);
typedef struct N9SysFile2chan N9SysFile2chan;
struct N9SysFile2chan
{
	
	Sys_FileIO**	ret;
	uchar	temps[12];
	String*	dir;
	String*	file;
};

void Sys_pipe(void*);
typedef struct N9Syspipe N9Syspipe;
struct N9Syspipe
{
	
	WORD*	ret;
	uchar	temps[12];
	Array*	fds;
};

void Sys_stream(void*);
typedef struct N9SysStream N9SysStream;
struct N9SysStream
{
	
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	src;
	Sys_FD*	dst;
	WORD	bufsiz;
};
*/
struct N9SysDial
{
    N9Req           req;
    Sys_Connection* ret;
    char*           d_addr;
    char*           d_local;
};

struct N9SysAnnounce
{
    N9Req           req;
    Sys_Connection* ret;
    char*           d_addr;
};

struct N9SysListen
{
	
	N9Req           req;
    Sys_Connection* ret;
    Sys_Connection* conn;
};


struct N9SysExport
{
    N9Req           req;
    int             ret;
    Sys_FD*         fd;
    char*           dir;
    int             flag;
};

struct N9SysSleep
{
    N9Req           req;
	int             ret;
	int             period;
};

/*
void Sys_fversion(void*);
typedef struct N9SysFversion N9SysFversion;
struct N9SysFversion
{
	
	struct{ WORD t0; String* t1; }*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	WORD	msize;
	String*	version;
};

void Sys_fauth(void*);
typedef struct N9SysFauth N9SysFauth;
struct N9SysFauth
{
	
	Sys_FD**	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	String*	aname;
};

*/
struct N9SysSpawn
{
    N9Req           req;
    int             ret;
};

struct N9SysPctl
{
    N9Req           req;
    int             ret;
    int             flags;
    int             numfds;
    int*            movefd;
};


/* unified syscall structure */
union N9SysReq {
	N9Req           req;
	N9SysOpen       open;
    N9SysSeek       seek;
    N9SysCreate     create;
    N9SysDup        dup;
    N9SysFildes     fildes;
    N9SysRead       read;
    N9SysReadn      readn;
    N9SysPread      pread;
    N9SysWrite      write;
    N9SysPwrite     pwrite;
    N9SysPrint      print;
    N9SysFprint     fprint;
    N9SysStat       stat;
    N9SysFstat      fstat;
    N9SysWstat      wstat;
    N9SysFwstat     fwstat;
    N9SysDirread    dirread;
    N9SysIounit     iounit;
    N9SysBind       bind;
    N9SysMount      mount;
    N9SysUnmount    unmount;
    N9SysRemove     remove;
    N9SysChdir      chdir;
    N9SysFd2path    fd2path;
/*
    N9SysFile2chan  file2chan;
    N9SysPipe       pipe;
    N9SysStream     stream;
*/
    N9SysDial       dial;
    N9SysAnnounce   announce;
    N9SysListen     listen;
    N9SysExport     export;
    N9SysSleep      sleep;
/*
    N9SysFversion   fversion;
    N9SysFauth      fauth;
*/
    N9SysPctl       pctl;
    N9SysSpawn      spawn;
};

/* maint and structure utility functions */
void            svc_events(int);
N9SysReq*       sysbuf(void*);
void*           make_vproc(void*);
void*           procpid(int);
int             pidproc(void*);
const char*     noderoot();
void            vproc_exit(void*);
void            free_cstring(char*);
void            free_fd(Sys_FD*);
void            free_dir(Dir*);
void            free_dirpack(Dirpack*);
void            free_sysconn(Sys_Connection*);

/* buffer operations */
Bytebuffer* bbNew(void);
void bbFree(Bytebuffer*);
int bbSetalloc(Bytebuffer*,const unsigned int);
int bbSetlength(Bytebuffer*,const unsigned int);
int bbFill(Bytebuffer*, const char fill);

/* Produce a duplicate of the contents*/
char* bbDup(const Bytebuffer*);

/* Return the ith char; -1 if no such char */
int bbGet(Bytebuffer*,unsigned int);

/* Set the ith char */
int bbSet(Bytebuffer*,unsigned int,char);

int bbAppend(Bytebuffer*,const char); /* Add at Tail */
int bbAppendn(Bytebuffer*,const void*,unsigned int); /* Add at Tail */

/* Insert 1 or more characters at given location */
int bbInsert(Bytebuffer*,const unsigned int,const char);
int bbInsertn(Bytebuffer*,const unsigned int,const char*,const unsigned int);

int bbCat(Bytebuffer*,const char*);
int bbCatbuf(Bytebuffer*,const Bytebuffer*);
int bbSetcontents(Bytebuffer*, char*, const unsigned int);
int bbNull(Bytebuffer*);

/* sysreq interface */
void            sysreq(void *p, void (*)(void*));
int             sysrep();

/* standard async system call and support */
void            Sys_open(uv_work_t*);
void            Sys_create(uv_work_t*);
void            Sys_dup(uv_work_t*);
void            Sys_fildes(uv_work_t*);
void            Sys_seek(uv_work_t*);
void            Sys_iounit(uv_work_t*);
void            Sys_stat(uv_work_t*);
void            Sys_fstat(uv_work_t*);
void            Sys_wstat(uv_work_t*);
void            Sys_fwstat(uv_work_t*);
void            Sys_dirread(uv_work_t*);
void            Sys_spawn(uv_work_t*);
void            Sys_pctl(uv_work_t*);
void            Sys_read(uv_work_t*);
void            Sys_readn(uv_work_t*);
void            Sys_pread(uv_work_t*);
void            Sys_print(uv_work_t*);
void            Sys_fprint(uv_work_t*);
void            Sys_write(uv_work_t*);
void            Sys_pwrite(uv_work_t*);
void            Sys_remove(uv_work_t*);
void            Sys_chdir(uv_work_t*);
void            Sys_fd2path(uv_work_t*);
void            Sys_dial(uv_work_t*);
void            Sys_announce(uv_work_t*);
void            Sys_listen(uv_work_t*);
void            Sys_bind(uv_work_t*);
void            Sys_unmount(uv_work_t*);
void            Sys_mount(uv_work_t*);
void            Sys_export(uv_work_t*);

/* non-standard sync and async calls */
void            sys_sleep(void*, int);
char*           sys_errstr(void *);
void            sys_werrstr(void *p, char* err);

unsigned int    sys_millisec();


