/* Copyright 2009, UCAR/Unidata and OPeNDAP, Inc.
   See the COPYRIGHT file for more information. */

#ifndef BYTEBUFFER_H
#define BYTEBUFFER_H 1

extern void* chkcalloc(size_t, size_t);
extern void* chkmalloc(size_t);
extern void* chkrealloc(void*,size_t);
extern void  chkfree(void*);

typedef struct Bytebuffer {
  int nonextendible; /* 1 => fail if an attempt is made to extend this buffer*/
  unsigned int alloc;
  unsigned int length;
  char* content;
} Bytebuffer;

extern void bbFree(Bytebuffer*);
extern int bbSetalloc(Bytebuffer*,const unsigned int);
extern int bbSetlength(Bytebuffer*,const unsigned int);
extern int bbFill(Bytebuffer*, const char fill);

/* Produce a duplicate of the contents*/
extern char* bbDup(const Bytebuffer*);

/* Return the ith char; -1 if no such char */
extern int bbGet(Bytebuffer*,unsigned int);

/* Set the ith char */
extern int bbSet(Bytebuffer*,unsigned int,char);

extern int bbAppend(Bytebuffer*,const char); /* Add at Tail */
extern int bbAppendn(Bytebuffer*,const void*,unsigned int); /* Add at Tail */

/* Insert 1 or more characters at given location */
extern int bbInsert(Bytebuffer*,const unsigned int,const char);
extern int bbInsertn(Bytebuffer*,const unsigned int,const char*,const unsigned int);

extern int bbCat(Bytebuffer*,const char*);
extern int bbCatbuf(Bytebuffer*,const Bytebuffer*);
extern int bbSetcontents(Bytebuffer*, char*, const unsigned int);
extern int bbNull(Bytebuffer*);

/* Following are always "in-lined"*/
#define bbLength(bb) ((bb)?(bb)->length:0U)
#define bbAlloc(bb) ((bb)?(bb)->alloc:0U)
#define bbContents(bb) ((bb && bb->content)?(bb)->content:(char*)"")
#define bbExtend(bb,len) bbSetalloc((bb),(len)+(bb->alloc))
#define bbClear(bb) ((void)((bb)?(bb)->length=0:0U))
#define bbNeed(bb,n) ((bb)?((bb)->alloc - (bb)->length) > (n):0U)
#define bbAvail(bb) ((bb)?((bb)->alloc - (bb)->length):0U)

#endif /*BYTEBUFFER_H*/
