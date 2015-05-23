#ifndef INTERP_FILE_H
#define INTERP_FILE_H

/* VM data structures (lua side) */
#include "node9.h"

/* lua FFI kernel call interface*/
#include "syscalls.h"

/* critical system constants */
#include "sysconst.h"


/* VM data structures (kernel side) follow */

enum { STRUCTALIGN = sizeof(int) };

typedef struct Sched sched_t;
typedef struct Progs Progs;
typedef struct FD FD;
/* typedef struct Heap Heap;
typedef struct Type Type;
extern  Type    Tchannel;
typedef struct Sys_FileIO Sys_FileIO;
#define WORD int
#define Array char
#define String char
typedef struct{ WORD t0; WORD t1; WORD t2; Channel* t3; } Sys_FileIO_read;
#define Sys_FileIO_read_size 16
#define Sys_FileIO_read_map {0x10,}
typedef struct{ WORD t0; Array* t1; WORD t2; Channel* t3; } Sys_FileIO_write;
#define Sys_FileIO_write_size 16
#define Sys_FileIO_write_map {0x50,}
#define Sys_FileIO_size 8

typedef struct{ Array* t0; String* t1; } Sys_Rread;
#define Sys_Rread_size 8
#define Sys_Rread_map {0xc0,}
typedef struct{ WORD t0; String* t1; } Sys_Rwrite;
#define Sys_Rwrite_size 8
#define Sys_Rwrite_map {0x40,}

struct Heap
{
        int     color;  
        ulong   ref;
        Type*   t;
        ulong   hprof; 
};

struct Type
{
        int     ref;
        void    (*free)(Heap*, int);
        void    (*mark)(Type*, void*);
        int     size;
        int     np;
        void*   destroy;
        void*   initialize;
        uchar   map[STRUCTALIGN];
};

struct Sys_FileIO
{
        Channel*        read;
        Channel*        write;
};

*/
struct Sched
{
        Lock        l;
        vproc_t*    runhd;
        vproc_t*    runtl;
        vproc_t*    head;
        vproc_t*    tail;
        //Rendez  irend;
        //int         idle;
        //int         nyield;
        //int         creating;
        //Atidle* idletasks;
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
        PRNSIZE = 1024,
        BIHASH  = 23,
        PQUANTA = 2048, /* prog time slice */

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


struct Progs
{
        Lock                l;      /* since access can now be concurrent */
        int                 id;
        int                 flags;
        Progs*              parent;
        Progs*              child;
        Progs*              sib;
        vproc_t*            head;   /* live group leader is at head */
        vproc_t*            tail;
};

vproc_t*    currun(void);
void        newgrp(vproc_t*);
void        tellsomeone(vproc_t*, char*);
int		    killprog(vproc_t*, char*);

#endif
