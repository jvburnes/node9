-- get machine info: this needs to be loaded *before* the node9 cdefs

-- first the misc machine info

ffi.cdef[[
extern char *hostcpu();
    
extern char *hostos();

/* the machine architecture word size in bytes, usually 4 or 8 */
extern int wordsize();

/* number of 32-bit words (ints) in the os machine state */
extern int jumpsize();

]]
