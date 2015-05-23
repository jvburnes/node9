#include "nine.h"

void
lock(Lock *l)
{
    os_spinlock(l);
}

int
canlock(Lock *l)
{
	return os_canspinlock(l);
}

void
unlock(Lock *l)
{
	os_spinunlock(l);
}

void
qlock(QLock *q)
{
	proc_t *p;

	lock(&q->use);
	if(!q->locked) {
		q->locked = 1;
		unlock(&q->use);
		return;
	}
	p = q->tail;
	if(p == 0)
		q->head = up;
	else
		p->qnext = up;
	q->tail = up;
	up->qnext = 0;
	unlock(&q->use);
	osblock();
}

int
canqlock(QLock *q)
{
	if(!canlock(&q->use))
		return 0;
	if(q->locked){
		unlock(&q->use);
		return 0;
	}
	q->locked = 1;
	unlock(&q->use);
	return 1;
}

void
qunlock(QLock *q)
{
	proc_t *p;

	lock(&q->use);
	p = q->head;
	if(p) {
		q->head = p->qnext;
		if(q->head == 0)
			q->tail = 0;
		unlock(&q->use);
		osready(p);
		return;
	}
	q->locked = 0;
	unlock(&q->use);
}

void
rlock(RWlock *l)
{
	qlock(&l->x);		/* wait here for writers and exclusion */
	lock(&l->l);
	l->readers++;
	canqlock(&l->k);	/* block writers if we are the first reader */
	unlock(&l->l);
	qunlock(&l->x);
}

/* same as rlock but punts if there are any writers waiting */
int
canrlock(RWlock *l)
{
	if (!canqlock(&l->x))
		return 0;
	lock(&l->l);
	l->readers++;
	canqlock(&l->k);	/* block writers if we are the first reader */
	unlock(&l->l);
	qunlock(&l->x);
	return 1;
}

void
runlock(RWlock *l)
{
	lock(&l->l);
	if(--l->readers == 0)	/* last reader out allows writers */
		qunlock(&l->k);
	unlock(&l->l);
}

void
wlock(RWlock *l)
{
	qlock(&l->x);		/* wait here for writers and exclusion */
	qlock(&l->k);		/* wait here for last reader */
}

void
wunlock(RWlock *l)
{
	qunlock(&l->k);
	qunlock(&l->x);
}
