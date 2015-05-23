/*
 * NODE9 SYSCALLS and data structures (shared kernel/lua) 
 */

/* kernel object types */
typedef struct Sys_Qid Sys_Qid;
typedef struct Sys_Dir Sys_Dir;
typedef struct Sys_FD Sys_FD;
typedef struct Statpack Statpack;
typedef struct Dirpack Dirpack;
typedef struct Sys_Connection Sys_Connection;
typedef struct Bytebuffer Bytebuffer;

/* kernel and interface objects */

struct Sys_Qid
{
	uint64_t    path;
	uint32_t    vers;
	uint8_t     qtype;
};

struct Sys_FD
{
    int         fd;
};

struct Sys_Dir
{
    char*       name;
    char*       uid;
    char*       gid;
    char*       muid;
    Sys_Qid     qid;
    uint32_t    mode;
    uint32_t    atime;
    uint32_t    mtime;
    int64_t     length;
    uint32_t    dtype;
    uint32_t    dev;
};

struct Dirpack
{
    int         num;
    Dir*        dirs;
};


struct Sys_Connection
{
        Sys_FD* dfd;
        Sys_FD* cfd;
        char*   dir;
};

struct Bytebuffer {
  int nonextendible; /* 1 => fail if an attempt is made to extend this buffer*/
  unsigned int alloc;
  unsigned int length;
  char* content;
};

