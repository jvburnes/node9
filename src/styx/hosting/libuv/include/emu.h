#ifndef EMU_H
#define EMU_H

#include <uv.h>

/*
 * hosted hypervisor and microkernel implementation-specifics for threads, synchronization, 
 * events, i/o, messaging, timers etc.
 */

/* 
 * libuv stuff 
 */

extern uv_key_t prdakey;
extern Dev*    devtab[];


#define up  ((proc_t*)uv_key_get(&prdakey))

typedef sigjmp_buf osjmpbuf;
#define	ossetjmp(buf)	sigsetjmp(buf, 1)

/* os and hosting-specific bindings */
typedef struct Osdep Osdep;
struct Osdep {
    unsigned long   self;           /* the thread id, not the thread pointer itself */
    uv_thread_t     thread;         /* the actual thread */
    uv_sem_t        sem;            /* OS wait semaphore */
};

#endif
