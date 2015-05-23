#ifndef NODE9_FILE_H
#define NODE9_FILE_H

/*
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <stdint.h>
*/

#include <stdbool.h>

#include <uv.h>

typedef struct kargs_s kargs_t;
void tramp(void *);
extern void termset(void);
extern void termrestore(void);
extern void cleanexit(int);

#include "dat.h"
#include "fns.h"
#include "error.h"
#include "kernel.h"
#include "version.h"

#include <luv.h>

/* Lua object meta tables */

#define NODE9_CHAN_T  "node9.chan"

/* trace stuff */
#define TRACE_INFO 0
#define TRACE_WARN 10
#define TRACE_ERROR 100

extern int tracelvl;

#define trace(lvl, ...) {if (tracelvl >= (lvl)) {time_t now = time(NULL); struct tm mdy; char timestr[70]; gmtime_r(&now, &mdy); strftime(timestr, sizeof(timestr), "%c", &mdy); fprintf(stderr,"%s ",timestr); fprintf(stderr, " " __VA_ARGS__); fprintf(stderr, "\n"); fflush(stderr); }}

#include <lua.h>                                /* Always include this when calling Lua */
#include <lauxlib.h>                            /* Always include this when calling Lua */
#include <lualib.h>                             /* Always include this when calling Lua */

kproc_t* new_kproc(void);
hproc_t* new_hproc(void);

/* command line args */
struct kargs_s {
    int argc;
    char **argv;
};

// define the queueing structures

enum Qtype
{
    Req_queue,
    Local_pipe,
    Thread_pipe,
};

#define REQ_QUEUE \
  enum Qtype type; \
  ngx_queue_t requests \

#define LOCAL_PIPE \
    REQ_QUEUE; \
    ngx_queue_t replies \

#define THREAD_PIPE \
    LOCAL_PIPE; \
    uv_mutex_t request_lock; \
    uv_mutex_t reply_lock \

// kernel request queue
typedef struct kpipe_s {
    REQ_QUEUE;
} kpipe_t; 

void panic(char *fmt, ...);
extern int hostuid;
extern int hostgid;
extern void setsigs(void);
LUALIB_API int luaopen_luv(lua_State *L);
void sysinit(void);


/*
 * Lua/Luv to Kernel Interfaces 
 */
 

/*
void Sys_announce(void*);
typedef struct F_Sys_announce F_Sys_announce;
struct F_Sys_announce
{
	WORD	regs[NREG-1];
	struct{ WORD t0; Sys_Connection t1; }*	ret;
	uchar	temps[12];
	String*	addr;
};
void Sys_aprint(void*);
typedef struct F_Sys_aprint F_Sys_aprint;
struct F_Sys_aprint
{
	WORD	regs[NREG-1];
	Array**	ret;
	uchar	temps[12];
	String*	s;
	WORD	vargs;
};
void Sys_bind(void*);
typedef struct F_Sys_bind F_Sys_bind;
struct F_Sys_bind
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	s;
	String*	on;
	WORD	flags;
};
void Sys_byte2char(void*);
typedef struct F_Sys_byte2char F_Sys_byte2char;
struct F_Sys_byte2char
{
	WORD	regs[NREG-1];
	struct{ WORD t0; WORD t1; WORD t2; }*	ret;
	uchar	temps[12];
	Array*	buf;
	WORD	n;
};
void Sys_char2byte(void*);
typedef struct F_Sys_char2byte F_Sys_char2byte;
struct F_Sys_char2byte
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	WORD	c;
	Array*	buf;
	WORD	n;
};
void Sys_chdir(void*);
typedef struct F_Sys_chdir F_Sys_chdir;
struct F_Sys_chdir
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	path;
};
void Sys_create(void*);
typedef struct F_Sys_create F_Sys_create;
struct F_Sys_create
{
	WORD	regs[NREG-1];
	Sys_FD**	ret;
	uchar	temps[12];
	String*	s;
	WORD	mode;
	WORD	perm;
};
void Sys_dial(void*);
typedef struct F_Sys_dial F_Sys_dial;
struct F_Sys_dial
{
	WORD	regs[NREG-1];
	struct{ WORD t0; Sys_Connection t1; }*	ret;
	uchar	temps[12];
	String*	addr;
	String*	local;
};
void Sys_dup(void*);
typedef struct F_Sys_dup F_Sys_dup;
struct F_Sys_dup
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	WORD	old;
	WORD	new;
};
void Sys_export(void*);
typedef struct F_Sys_export F_Sys_export;
struct F_Sys_export
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	c;
	String*	dir;
	WORD	flag;
};
void Sys_fauth(void*);
typedef struct F_Sys_fauth F_Sys_fauth;
struct F_Sys_fauth
{
	WORD	regs[NREG-1];
	Sys_FD**	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	String*	aname;
};
void Sys_fd2path(void*);
typedef struct F_Sys_fd2path F_Sys_fd2path;
struct F_Sys_fd2path
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[12];
	Sys_FD*	fd;
};
void Sys_fildes(void*);
typedef struct F_Sys_fildes F_Sys_fildes;
struct F_Sys_fildes
{
	WORD	regs[NREG-1];
	Sys_FD**	ret;
	uchar	temps[12];
	WORD	fd;
};
void Sys_file2chan(void*);
typedef struct F_Sys_file2chan F_Sys_file2chan;
struct F_Sys_file2chan
{
	WORD	regs[NREG-1];
	Sys_FileIO**	ret;
	uchar	temps[12];
	String*	dir;
	String*	file;
};
void Sys_fprint(void*);
typedef struct F_Sys_fprint F_Sys_fprint;
struct F_Sys_fprint
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	String*	s;
	WORD	vargs;
};
void Sys_fstat(void*);
typedef struct F_Sys_fstat F_Sys_fstat;
struct F_Sys_fstat
{
	WORD	regs[NREG-1];
	struct{ WORD t0; uchar	_pad4[4]; Sys_Dir t1; }*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
};
void Sys_fversion(void*);
typedef struct F_Sys_fversion F_Sys_fversion;
struct F_Sys_fversion
{
	WORD	regs[NREG-1];
	struct{ WORD t0; String* t1; }*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	WORD	msize;
	String*	version;
};
void Sys_fwstat(void*);
typedef struct F_Sys_fwstat F_Sys_fwstat;
struct F_Sys_fwstat
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	uchar	_pad36[4];
	Sys_Dir	d;
};
void Sys_iounit(void*);
typedef struct F_Sys_iounit F_Sys_iounit;
struct F_Sys_iounit
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
};
void Sys_listen(void*);
typedef struct F_Sys_listen F_Sys_listen;
struct F_Sys_listen
{
	WORD	regs[NREG-1];
	struct{ WORD t0; Sys_Connection t1; }*	ret;
	uchar	temps[12];
	Sys_Connection	c;
};
void Sys_millisec(void*);
typedef struct F_Sys_millisec F_Sys_millisec;
struct F_Sys_millisec
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
};
void Sys_mount(void*);
typedef struct F_Sys_mount F_Sys_mount;
struct F_Sys_mount
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	Sys_FD*	afd;
	String*	on;
	WORD	flags;
	String*	spec;
};
*/

//
// SYSTEM CALL PACKETS
//


// base syscall parameters
// here is where we bind the interpreter state to the inferno Proc
#define NODE9_SYSCALL \
  proc_t*       proc;           /* node9 kernel or user proc */ \
  luv_state_t*  state;          /* luv fiber context (base thread or hosted fiber) */ \
  uv_work_t     req             /* libuv req structure */ \
  
// generic Sys_call structure
typedef struct F_Sys_call F_Sys_call;
struct F_Sys_call
{
    NODE9_SYSCALL;
};

// open a channel and return descriptor
void Sys_open(uv_work_t*);

typedef struct F_Sys_open F_Sys_open;
struct F_Sys_open
{
    NODE9_SYSCALL;    
    char*     path;
    int       mode;
    int       ret;
};

void Sys_dirread(uv_work_t*);
typedef struct F_Sys_dirread F_Sys_dirread;
struct F_Sys_dirread
{
    NODE9_SYSCALL;
	FD*	fd;
};


// free an unused descriptor
void Sys_freeFD(uv_work_t*);

typedef struct F_Sys_freeFD F_Sys_freeFD;
struct F_Sys_freeFD
{
    NODE9_SYSCALL;    
	FD*     fd;
};


// syscall work is done, so demarshall
void Sys_req_complete(uv_work_t*, int);

/*
void Sys_pctl(void*);
typedef struct F_Sys_pctl F_Sys_pctl;
struct F_Sys_pctl
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	WORD	flags;
	List*	movefd;
};
void Sys_pipe(void*);
typedef struct F_Sys_pipe F_Sys_pipe;
struct F_Sys_pipe
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Array*	fds;
};
void Sys_pread(void*);
typedef struct F_Sys_pread F_Sys_pread;
struct F_Sys_pread
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	Array*	buf;
	WORD	n;
	uchar	_pad44[4];
	LONG	off;
};
void Sys_print(void*);
typedef struct F_Sys_print F_Sys_print;
struct F_Sys_print
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	s;
	WORD	vargs;
};
void Sys_pwrite(void*);
typedef struct F_Sys_pwrite F_Sys_pwrite;
struct F_Sys_pwrite
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	Array*	buf;
	WORD	n;
	uchar	_pad44[4];
	LONG	off;
};
void Sys_read(void*);
typedef struct F_Sys_read F_Sys_read;
struct F_Sys_read
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	Array*	buf;
	WORD	n;
};
void Sys_readn(void*);
typedef struct F_Sys_readn F_Sys_readn;
struct F_Sys_readn
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	Array*	buf;
	WORD	n;
};
void Sys_remove(void*);
typedef struct F_Sys_remove F_Sys_remove;
struct F_Sys_remove
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	s;
};
void Sys_seek(void*);
typedef struct F_Sys_seek F_Sys_seek;
struct F_Sys_seek
{
	WORD	regs[NREG-1];
	LONG*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	uchar	_pad36[4];
	LONG	off;
	WORD	start;
};
void Sys_sleep(void*);
typedef struct F_Sys_sleep F_Sys_sleep;
struct F_Sys_sleep
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	WORD	period;
};
void Sys_sprint(void*);
typedef struct F_Sys_sprint F_Sys_sprint;
struct F_Sys_sprint
{
	WORD	regs[NREG-1];
	String**	ret;
	uchar	temps[12];
	String*	s;
	WORD	vargs;
};
void Sys_stat(void*);
typedef struct F_Sys_stat F_Sys_stat;
struct F_Sys_stat
{
	WORD	regs[NREG-1];
	struct{ WORD t0; uchar	_pad4[4]; Sys_Dir t1; }*	ret;
	uchar	temps[12];
	String*	s;
};
void Sys_stream(void*);
typedef struct F_Sys_stream F_Sys_stream;
struct F_Sys_stream
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	src;
	Sys_FD*	dst;
	WORD	bufsiz;
};
void Sys_tokenize(void*);
typedef struct F_Sys_tokenize F_Sys_tokenize;
struct F_Sys_tokenize
{
	WORD	regs[NREG-1];
	struct{ WORD t0; List* t1; }*	ret;
	uchar	temps[12];
	String*	s;
	String*	delim;
};
void Sys_unmount(void*);
typedef struct F_Sys_unmount F_Sys_unmount;
struct F_Sys_unmount
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	s1;
	String*	s2;
};
void Sys_utfbytes(void*);
typedef struct F_Sys_utfbytes F_Sys_utfbytes;
struct F_Sys_utfbytes
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Array*	buf;
	WORD	n;
};
void Sys_werrstr(void*);
typedef struct F_Sys_werrstr F_Sys_werrstr;
struct F_Sys_werrstr
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	s;
};
void Sys_write(void*);
typedef struct F_Sys_write F_Sys_write;
struct F_Sys_write
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Sys_FD*	fd;
	Array*	buf;
	WORD	n;
};
void Sys_wstat(void*);
typedef struct F_Sys_wstat F_Sys_wstat;
struct F_Sys_wstat
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	String*	s;
	uchar	_pad36[4];
	Sys_Dir	d;

};
#*/
#define Sys_PATH "$Sys"
#define Sys_Maxint 2147483647
#define Sys_QTDIR 128
#define Sys_QTAPPEND 64
#define Sys_QTEXCL 32
#define Sys_QTAUTH 8
#define Sys_QTTMP 4
#define Sys_QTFILE 0
#define Sys_ATOMICIO 8192
#define Sys_SEEKSTART 0
#define Sys_SEEKRELA 1
#define Sys_SEEKEND 2
#define Sys_NAMEMAX 256
#define Sys_ERRMAX 128
#define Sys_WAITLEN 192
#define Sys_OREAD 0
#define Sys_OWRITE 1
#define Sys_ORDWR 2
#define Sys_OTRUNC 16
#define Sys_ORCLOSE 64
#define Sys_OEXCL 4096
#define Sys_DMDIR -2147483648
#define Sys_DMAPPEND 1073741824
#define Sys_DMEXCL 536870912
#define Sys_DMAUTH 134217728
#define Sys_DMTMP 67108864
#define Sys_MREPL 0
#define Sys_MBEFORE 1
#define Sys_MAFTER 2
#define Sys_MCREATE 4
#define Sys_MCACHE 16
#define Sys_NEWFD 1
#define Sys_FORKFD 2
#define Sys_NEWNS 4
#define Sys_FORKNS 8
#define Sys_NEWPGRP 16
#define Sys_NODEVS 32
#define Sys_NEWENV 64
#define Sys_FORKENV 128
#define Sys_EXPWAIT 0
#define Sys_EXPASYNC 1
#define Sys_UTFmax 4
#define Sys_UTFerror 65533
#define Sys_Runemax 1114111
#define Sys_Runemask 2097151


#endif
