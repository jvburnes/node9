#ifndef NINE_FILE_H
#define NINE_FILE_H

#include <stdbool.h>
#include <uv.h>
#include "queue.h"
#include "dat.h"
#include "fns.h"
#include "error.h"
#include "kernel.h"

typedef struct kargs_s kargs_t;
void tramp(void *);
extern void termset(void);
extern void termrestore(void);


/* trace stuff */
#define TRACE_INFO 0
#define TRACE_WARN 10
#define TRACE_ERROR 100
#define TRACE_DEBUG 1000

extern int tracelvl;

#define trace(lvl, ...) {if (lvl <= (tracelvl)) {time_t now = time(NULL); struct tm mdy; char timestr[70]; gmtime_r(&now, &mdy); strftime(timestr, sizeof(timestr), "%c", &mdy); print("%s ",timestr); print(" " __VA_ARGS__); print("\n"); }}

#include <lua.h>                                /* Always include this when calling Lua */
#include <lauxlib.h>                            /* Always include this when calling Lua */
#include <lualib.h>                             /* Always include this when calling Lua */


/* command line args */
struct kargs_s {
    int argc;
    char **argv;
};


void panic(char *fmt, ...);
extern int hostuid;
extern int hostgid;
extern void setsigs(void);
void sysinit(void);

#endif
