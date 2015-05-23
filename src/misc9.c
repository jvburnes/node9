#include "nine.h"

int cflag = 0;
int sflag = 0;


/* FIX: These variables should be exposed by the lua garbage collector so devmem can
 * report on them:
 * gcnruns, gcsweeps, gcbroken, gchalted, gcepochs, gcdestroys, gcinspects, gcbusy, gcidle, gcidlepass, gcpartial
 *
 * For now just set them to zero here.
 */
 
ulong	gcnruns = 0;
ulong	gcsweeps = 0;
ulong	gcbroken = 0;
ulong	gchalted = 0;
ulong	gcepochs = 0;
uvlong	gcdestroys = 0;
uvlong	gcinspects = 0;
uvlong	gcbusy = 0;
uvlong	gcidle = 0;
uvlong	gcidlepass = 0;
uvlong	gcpartial = 0;

 
/* FIX: temporary prog dev support functions so devdup can compile
 */

static int
progqidwidth(Chan *c)
{
        char buf[32];

        return sprint(buf, "%lud", c->qid.vers);
}

int
progfdprint(Chan *c, int fd, int w, char *s, int ns)
{
        int n;

        if(w == 0)
                w = progqidwidth(c);
        n = snprint(s, ns, "%3d %.2s %C %4ld (%.16llux %*lud %.2ux) %5ld %8lld %s\n",
                fd,
                &"r w rw"[(c->mode&3)<<1],
                devtab[c->type]->dc, c->dev,
                c->qid.path, w, c->qid.vers, c->qid.type,
                c->iounit, c->offset, c->name->s);
        return n;
}


void stackdump_g(lua_State* l)
{
    int i;
    int top = lua_gettop(l);
 
    printf("total in stack %d\n",top);
 
    for (i = 1; i <= top; i++)
    {  /* repeat for each level */
        int t = lua_type(l, i);
        switch (t) {
            case LUA_TSTRING:  /* strings */
                printf("string: '%s'\n", lua_tostring(l, i));
                break;
            case LUA_TBOOLEAN:  /* booleans */
                printf("boolean %s\n",lua_toboolean(l, i) ? "true" : "false");
                break;
            case LUA_TNUMBER:  /* numbers */
                printf("number: %g\n", lua_tonumber(l, i));
                break;
            default:  /* other values */
                printf("%s\n", lua_typename(l, t));
                break;
        }
        printf("  ");  /* put a separator */
    }
    printf("\n");  /* end the listing */
}


