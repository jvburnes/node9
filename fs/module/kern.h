typedef
struct Qid
{
        uint64_t    path;
        uint32_t    vers;
        uint8_t     type;
} Qid;

typedef
struct Dir {

        /* system-modified data */
        uint32_t    type;   /* server type */
        uint32_t    dev;    /* server subtype */
        /* file data */
        Qid         qid;    /* unique id from server */
        uint32_t    mode;   /* permissions */
        uint32_t    atime;  /* last read time */
        uint32_t    mtime;  /* last write time */
        int64_t     length; /* file length */
        char        *name;  /* last element of path */
        char        *uid;   /* owner name */
        char        *gid;   /* group name */
        char        *muid;  /* last modifier name */
} Dir;

