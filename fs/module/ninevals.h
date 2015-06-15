/* plan9/inferno-specific value types */
#if defined(__linux__)
  typedef unsigned long long int uvlong;
  typedef long long int vlong;
  typedef vlong u64int;
#else
  typedef  int64_t vlong;
  typedef	uint64_t uvlong;
#endif
  typedef unsigned long ulong;
  typedef unsigned short ushort;
  typedef unsigned int uint;
  typedef unsigned char uchar;
