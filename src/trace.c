#define MAXMESSAGES 0x100
#define MSGMASK (MAXMESSAGES-1)

int64_t msgnum = -1;

static char*[] messages[MAXMSGS];
static uint64_t timestamp[MAXMSGS];
static unsigned long tid[MAXMSGS];


void trace(char* msg) {
    ++msgnum;
    int64_t mnum = msgnum&MSGMASK;
    messages[mnum] = msg;
    timestamp[mnum] = uv_hrtime();
    tid[mnum] = uv_thread_self();
}
