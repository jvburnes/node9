#include "node9.h"
#include "interp.h"
#include "isa.h"
//#include "kernel.h"


/*
 * The following comments document the overall node9 libary and kernel system.
 * The system calls in this file inplemet the basic node9 libraries.
 *
 * -- Inferno to Node9 --
 *
 * In the previous Inferno architecture a single virtual machine
 * that implemented the 'dis' instruction set was shared among all running
 * threads.  Threads were scheduled to run only when the thread using the VM
 * was waiting for IO. This means that only one OS thread can execute at 
 * a time in Inferno.  It did tend also to make the shared memory and CPU architecture
 * somewhat more obvious -- at least at first blush.  
 *
 * The downside is that it prevented true parelleism on a multicore backplane
 * (short of running separate heavyweight OS processes communicating through 
 * the operating systems pipe layer or TCP loopback transports.)  
 *
 * The way we get around this CPU limitation in node9 is to treat each node9 
 * instance as a single thread bound to a core which manages it's own virtual
 * CPU (Lua here).  If you want a new *OS* thread we spawn a new node9 which 
 * owns it's own namespace, devices, etc.  The original thread can then import 
 * the CPU namespace of the new thread using a high peformance FIFO.
 *
 * While heavyweight OS processes and shared memory messaage boxs could be used
 * to work around this Inferno limitation, that mechanism isn't universally portable.
 *
 * Much better to use multiple threads and a VM layer to emulate hosted processes
 * which takes advantage of the implicit shared memory of OS threads. Doing so
 * creates a scalable multicore architecture of cooperating Lua VCPU threads
 * at the slight cost of adding an extension to the /prog ctl interface to allow 
 * remote process startup.  The benefit is that inter-core memory mapping 
 * (shared backplane memory) is more efficient when used for explicit information
 * sharing rather than heuristic mapping of on-the-fly data structures.  This is
 * because explicit sharing greatly increases the probability of information coherence
 * between shared structures thus minimizing accidental cache invalidation.
 *
 * This inter-thread communications channel uses an extremely high-performace,
 * cache-coherent, lock-free FIFO which also completely bypasses 9p serialization 
 * and TCP stack processing. The only data passed on these channels are the raw
 * system fcalls.  Atomic FIFO operations ensure that the data on each
 * side of the channel barrier is safe. The Lua sandbox constructed by the
 * node9 kernel guarantees that lua scripts cannnot corrupt the data once
 * transferred across this barrier.
 *
 * Since we don't use a single global dis VM lock, we are free to make
 * direct syscalls into the kernel device interface in 'sysfile' without
 * releasing and reacquiring the VM.
 *
 * The devices know which calls block, so the lua fiber is descheduled,
 * the syscall placed in a request queue and the system call is executed in
 * the next sweep of the event loop.  The event loop tracks completion based on
 * stream handles, which in the case of node9/inferno is the FID/channel.  The
 * "watcher" for channel readiness synthesizes the ready state by tracking 
 * the completion state of each of its wait states.  If a file open requires
 * a two blocking calls, those calls are scheduled as workers. As each of them
 * completes, the watcher tracking state is updated.  When the final wait state
 * is complete, the handle is ready and the calling fiber is made ready.
 * 
 * If the call doesn't block it will be executed directly using either
 * libuv or the relevant server code.  This means that badly behaved 
 * fibers that execute non-blocking operations can starve other
 * fibers and prevent kernel operation.  Of course this is always the 
 * case when a high privilege process takes control.  There are three
 * mechanisms that limit this risk.  (1) All node9 I/O operations 
 * transparently perform a coroutine yield during the system call regardless
 * if the operation blocks or not.
 * (2) Each node9 user that logs in is allocated their own VCPU (OS thread).
 * (3) The underlying Lua VM can be instrumented to execute a 
 * selectable quanta of virtual instructions before being
 * forced to yield - making node9 optionally preemptive.  The only
 * remaining risk is a buggy or compute bound fiber.
 *
 * Though node9 threads share resident kernel driver and service code,
 * they remain independent by referencing dynamic structures (device lists,
 * buffers, etc) owned by the threads root process,  The root process handle
 * is saved in thread-local storage as 'prdakey' at thread creation time 
 * and is accessed using the "up" handle in the kernel source code.
 * 
 * The only other bit of complexity is the issue of driver code sharing.
 * If drivers are pre-configured at build-time then the amount of driver
 * code is equal to the needs of all possible concurrent threads.  This isn't
 * usually a problem as the total number of drivers within a single node9
 * build is generally limited.  However, the underlying inferno stack
 * does include a dynamic kernel module loader that allows the node9
 * build to only load those drivers required at runtime.  Since you 
 * access it via an inferno device, you could even remotely load kernel
 * modules for with which you shared the proper namespace services.
 * 
 * For now, a single compile-time driver table will be shared between
 * the threadcores.  
 *
 * -- Memory and Interrupt Handling --
 *
 * Inferno was designd to run on resource contrained systems, possibly without
 * a host operating system.  As such it doesn't make any assumptions about
 * available memory managers.  Since it's responsible for allocating memory
 * for the kernel as well as user processes, it provides versions of malloc,
 * calloc, realloc etc.  These functions are used by the kernel as well as the
 * dis virtual machine.  This is where things can get a little tricky.  There
 * are some interfaces between the dis VM garbage collector and the inferno 
 * memory manager that are not very well documented. While their function is
 * obviously required if the memory manager is to release collected garbage,
 * these functions have been temporaily disabled until their interfaces are
 * well understood and to enable early compiles.
 *
 * The raises another issue.  While the inferno memory manager is mostly functional
 * for kernel and driver requirements, it must be interfaced with the lua/luajit
 * VM memory allocation calls if the underlying inferno OS stack is to control, 
 * monitor and report on usage of OS memory regions -- a rather critical
 * operating system function.  Lua(JIT) has well-documented calls to replace the
 * native memory allocation subsystem with a system-specific one.  Node9 will be
 * able to use infernos memory manager and will integrate it's the VMs garbage collector
 * with inferno's "free" mechanism.  (Initial perusal of the dis garbage collector seems to
 * indicate that it's a tri-color collector.  It's undertain how that will impact the 
 * allocation interface).  The trick here is to let Inferno manage it's own kernel
 * data structures, expose them to Lua when appropriate and allow Lua to otherwise
 * manage and garbage collect it's own objects -- even if it's using the underlying
 * Inferno malloc and free.
 *
 * -- Evented IO Subsystem --
 * 
 * Part of the inferno subsystem refactor was implementing the low-level drivers,
 * asynchronous services, timers etc using an evented IO callback model.  This 
 * system, based on libuv, abstracts the underlying OS stream IO, network, threading
 * and async mechanisms under a single unified and portable interface,  On reactor
 * systems (POSIX) where processes register interest in a type of device and the OS let's them
 * know when that device is ready, libuv uses select-like mechanisms.  On "proactor" 
 * systems (like Windows), where processes request an IO operation and the OS generates
 * a callback when I/O is finished, libuv uses IO request and completion queues.  The 
 * libuv system also abstracts the concept of asynchronous I/O requests via "overlapped"
 * I/O on Windows and I/O worker thead pools on POSIX.
 *
 * Except for timer and pure async notification, libuv exposes a minimal stream I/O model.
 * A process registers interest in several types of stream I/O or async events.  libuv then uses
 * system-dependent drivers and interrupts to sweep the system for all current events -- calling
 * back into the process should it need memory allocated for low-level IO operations.
 * 
 * libuv then uses a single-threaded event loop to dispatch the collected events to the registered
 * listeners (via callbacks) -- essentially converting an asynchronous process into a synchronous
 * one. In this way the processes' event listeners are guaranteed that there are no contention issues
 * which require locking.  (This callback mechanism would normally be a tediuous mode of programming
 * as it requires explicit passing of process state through "batons" to succeedng callbacks.  More
 * about that later.)
 *
 * Of course this doens't mean that locking is never required, but it means that critical 
 * code sections are limited to places where threads interact with each other.  Most of this
 * is handled automatically using libuv async workers and notification listeners.  Obvious 
 * places where locking is unavoidable are concurrent async workers that contend for the same
 * system resources or kernel data structures.  The only way around this would be to assign
 * one OS thread and kernel for each Prog.  That would probably strain system resources in
 * an attempt to avoid locks altogether where spinlocks almost always work.  (This might be an
 * interesting place to experiment though -- possibly where sharing is explicit, the thread is
 * long-lived and and I/O throughput is paramount.  This is where we plan to go anyway with 
 * our version of the kproc structure.
 *
 * Occasionally new thread-to-thread interfaces are required for highly specialized 
 * inter-thread communications.  These can be implemented by writing a new libuv stream
 * driver or using the built-in async notification mechanism with custom code.
 *
 * The primary challenge then is to un-roll each inferno system device, one-at-a-time, into 
 * the evented IO model.  The first devices will obviously be devroot, devenv and devconsole.
 *
 * (NOTE to self: Since the libuv callback mechanisms require the callback to interface back to
 *  the kcall requester (lua here), initial refactoring will simply be wrapping kcalls with async
 *  workers using the already provided locking.  Create two versions of the kernel calls.  Versions
 *  that start with styx_<call> wrap the entire kernel call in a libuv async worker which maps 
 *  back to the lua interface.  Internal versions are still called kopen, kwrite etc.  The styx_
 *  version will still make calls into the internal kernel calls.  It may actually be easier to 
 *  write the styx_ versions directly to the sys->call interface so you always end up with 
 *  a 1:1 mapping.  Later releases may implement increasing amount of calls in pure lua.  The 
 *  general pattern is that, if the kernel code is already executing in async mode, you can call
 *  the internal version -- in fact you would have to because the styx_versions callback to a 
 *  lua requester, not the kernel C code.)
 *
 * -- The Shared Namespace "Big Concept" --
 * 
 * Getting back to inferno.  At it's lowest layers inferno is based on the Plan9 operating
 * system.  Plan9 uses relatively conventional OS concepts like spinlocks, semaphores and
 * rpc rendezvous to deal with asynchronous contention and request scheduling.  At the middle
 * layers of the os stack, these request calls appear to be sequential, but at the lower layers
 * they require a relatively complex and difficult to debug mixture of lock contention and sheduling
 * algorithms.
 *
 * Unrolling these into a libuv evented IO model has two primary effects:  (1) It makes 
 * debugging asynchronous OS issues much more straightforward and (2) it exposes the essential
 * async nature of the OS directly to the systems programmer.  While (1) is undeniably positive
 * and comes with only a minor performace hit, (2) has both it's pros and cons.  While (2)
 * allows a higher degree of control since you're developing directly to the async interface,
 * async callbacks and baton passing as a primary programming model don't scale very well,
 * Besides obscuring the functional and object interaction models, it eventually makes the OS
 * code harder to read and maintain. Since programming an OS is never trivial, greater modularity and
 * maintainability in a the code base is a highly desirable trait.
 *
 * So how do we deal with all of the asych callbacks and baton passing?  Though the issue
 * seems insurmountable, every problem is an opportunity in disguise.
 * and kernelspace are nearly unified and only separated by the kernel sandboxing of the lua VM.
 * 
 * That means that the node9 operating system services can be written using lua coroutines running
 * under full priveleges.  This unrolls the evented I/O model into nice, clean sequential fibers
 * solving the OS async problems and exposing the node9/inferno model via a functional-oo interface.
 * This is essentially what coroutines do best.  They allow software engineers to convert asynchronous
 * callbacks into sequential programming via C.A.R Hoare Communicating Sequential Process
 * patterns.  These can be molded at the developers desire to create whichever patterns are 
 * useful like functional, map/filter/reduce, iterator/generator, streams, channel attach, 
 * producer-consumer, publish/subscribe and resource/tracker.
 * 
 * -- Scaling Up To Arbitrary Topologies -- 
 *
 * Each new thread (or user that "logs on") is allocated it's own virtual CPU, devices and 
 * namespace. Security is maintained by the user attaching to the base-thread by mounting 
 * into its namespace using styx protocol over high-performance FIFOs.  This is very similar
 * to the original IBM concept of a virtual machine as a virtual device hypervisor (via VM-CP,
 * later VM/CMS/SP etc).
 *
 * VM-CPs idea of a virtual CPU, console, card reader and keypunch may seem incredibly quaint to
 * us now, but it provided the basis for this kind of hypervisor.  In this way node9 is very much a 
 * host-based hypervisor (metavisor?), that provides a VCPU and devices.  Node9 extends this 
 * basic concept by leveraging inferno's unified namespace services, 
 * 
 * The libuv evented IO model and luajit's high-performance scheme-like JIT environment create
 * a productive, high-performance and secure development model.  Due to the benefits of inferno's
 * underlying styx namespace protocol, node9 can transparently scale from a single fiber-rich
 * threadcore to a hyper-torus computing surface.  Lightweight processes can be started anywhere on
 * this compute surface and will run unaffected by host CPU, device/service details or intervening 
 * transport protocols -- whether 40Gb/s switched Infiniband or carrier pidgeon protcol.
 *
 * While it's true that node9 is beginning it's life around the flexible and interactive lua VM,
 * there's no reason that additional VCPUs couldn't be written to make an array of VCPU "personalities"
 * based on python, javascript, scheme, ruby or opencl kernel available to the topology.  The /prog
 * interface abstracts the details of loading and executing a program to an available VCPU that matches
 * the program type.  Hybrid VCPUs that abstract compiler interfaces like llvm or direct bindings
 * to low-level hypervisors like KVM could be created.  Indeed the styx/9p protocol that node9
 * uses allows it to participate in any topology that also uses it.  This includes Google Go
 * as well obviously plan9, inferno, v9fs on Linux and any software system that has libraries 
 * for 9p like Java etc.
 *
 * In this way node9 can create arbitrarily sophisticated concurrent computing topologies.
 *
 * -- Some Challenges --
 *
 * Any distributed computing techology that relies on RPC mechanisms for command and
 * I/O is sensitive to network latency.  The simplest example is file transfer. At the 
 * styx level a file transfer can be as simple as a file copy from one namespace to another.
 * Read from source and write to the destination file until you hit end-of-file.  
 *
 * Unfortunately, if the developer who implements the copy program simply sits in a loop
 * reading relatively small amounts from a remote source and writing it a local destination, the
 * speed at which the copy occurrs is dependent on the time it takes a read request to complete.
 * For example, on a local system an I/O buffer read could complete in microseconds.  The 
 * latency for a read request to be received and fullfilled by the source is negligable.  
 *
 * On a remote machine where the time for a request to traverse a series of namespace mounts,
 * packet routes and light travel time could easily approach 1/2 second or even longer, the
 * latency for the read request to be received and the responded to will prevent the next
 * request from being sent *and the amount you're waiting for is a very small percentage of
 * total available connection bandwidth being wasted each millisecond*.  But how can you send
 * the next request until you know the current buffer has been received and written to disk?
 * In network engineering this is known as the channel throughput problem.  Using well known
 * formula actual channel throughput can be calculated and response latency is a critical 
 * component.
 *
 * There are two basic ways to deal with this issue.  One is directly at the programmatic 
 * layer where the developer knows this is an issue an makes special provisions.  This can 
 * be handled directly through libuv at the OS, systems or application layer.  For example, 
 * a person writing a 'cp' function could offload the transfer to an async file transfer 
 * worker which compensates for network latency and issues callbacks as it reaches various
 * stages of the transfer. This is usually the best solution.  In fact, this is such a common 
 * problem that libuv already has a built-in worker for high performance file transfer.
 * 
 * The second way of increasing performance is by using a number of heuristics which combine
 * cacheing algorithms, pre-fetch and rpc batching to boost performance when possible. 
 * Cacheing simply stores the results of previous requests in case of re-request.  Pre-fetch
 * uses a heuristic to predict that a process is going to request the next 1024 bytes of a 
 * file if it's performed that same request over some number of times depending on threshold
 * values.  It can issue a series of 1024-byte request immdiately or simply create a sliding
 * window where after a certain threshold it proxies the request for the user, doubling and
 * re-doubling the effective request size and breaking them back down for the caller.
 * The downside is when the proxy mispredicts and consumes bandwidth and memory that are
 * never used.  Obviously this only works for reading, but in the best cases it
 * can approach the explicit async file transfer in performance.
 * 
 * For the developer and systems engineer the best way to deal with these issues is to keep 
 * high-performance computing elements on a semi-local switched transport. Some
 * examples are motherboard buses like hypertransport, card interfaces like PCIe or NUMA
 * backplane solutions like like Infiniband.  Infiniband can be leveraged using TCP
 * emulation or by directly leveraging the infiniband drivers at the node9 layer.
 *
 * Small command and control interfaces, while exposed to the same issues generally aren't
 * an issue because they don't require the extreme performance needed by file transfers
 * or multimedia transfers.  This ceases to be the case when maximum interactive wait times
 * are exceeded.  For example, if sending a command to a system on the other side of the
 * planet (or on another planet), RPC or local command batching may be mandatory.
 *
 * Generally the low-level inferno modules compensate as best as they can in the default
 * situations.  Systems and software engineers should take all of these factors into account
 * when scalability, latency and robustness are key.
 *
 * Node9's combination of easy driver and service creation, high-performance scripting 
 * and evented IO model makes it possible to realize the promise of its inferno
 * next generation architecture. 
 * 
 * Obvious applications of the architecture are mass-parallel compute clusters, map-reduce
 * arrays, VM control systems, reconfigurable soft-switch networks and monitors, GPGPU computing and
 * secure MMORPGs.  Its potential to become a true "cloud" OS running tightly integrated with web
 * front-ends like nodejs' libuv event loop or nginx's lua subsystem should be obvious to those
 * who work in the high-performance computing, communications, security or IAAS communities.
 *
 * Ease Of Use
 *
 * The rate at which any system is absorbed into the community is related to a number of factors.  
 * Primary among these are ease-of-use, reliability, maintainability, utility and performance. 
 * It is the sincere intent of the node9 authors to make well-tested and reliable releases. These
 * will come with a good default systems library, a great development interface and easy-to-use
 * management tools.  To this end the following libraries and tools will be integrated as soon
 * as is possible into the default install.
 *
 * Unit test and live testing interfaces: We're a distributed OS so we insist on "eating our own
 * dog food" by providing unit and live subsystem testing to ensure system quality before release
 * and thoughout the app lifecycle.
 * 
 * User libraries: The basic set of inferno system and programming modules including syscall,
 * math, crypto etc.  Of course most of the Lua libraries are availale and usable as IO, compute
 * and system call blocking are taken into account.  Of these, the great functional programming
 * library 'penlight' is included as an optional module.
 *
 * IDE: A quick and covenient interface for development and debug is especially important for a 
 * distributed computing environment.  Currently the most interactive and powerful IDE we're
 * aware of for distributed lua program development is ZBS (ZeroBraneStudio).  It's as extensible
 * as emacs, intuitive as notepad and fast as greased lightening.  It's already used in a number
 * of Lua game development systems and provides hyperlinked self-help and wizards directly integrated
 * into the code buffers.
 *
 * It can perform both local and remote script debugging transparently and features a command output
 * buffer as well as local and remote lua consoles.  This console could be mapped straight into a 
 * node9 'cons' device executing a lua shell in any node9 thread in the distributed OS.  The IDE
 * could even give a view into the distributed topology allowing you to drag and drop node9 threads
 * onto the compute surface or lua apps onto node9 threads.
 *
 * Management UI: A simple node9 compute topology user interface bound to sajax
 * interface into the node9 namespace would give dircect access into system management.. A sexy
 * HTML5/threed jquery interface would greatly extend the ability to configure and leverage
 * the node9 cloud.  Obvious services such as system administration, user management, security
 * management, core allocation and affinity as well as service management would greatly add to 
 * node9's value.  This should be very easy to implement as a standalone web service using luv
 * or libuv's http interface or by merging it at the libuv layer with nodejs.
 *
 * ADDITIONAL NOTES:
 *
 * PROCESS MODEL
 *
 * node9 uses a "thread-core" model where many small fiber processes are managed and serviced
 * by a kernel process.  In this way many lightweight fibers can execute within a single CPU
 * core within the same thread.  Additional OS threadcores,(each with its own kproc) can be
 * constructed with each having its set of fibers.  Synchronization between kprocs happens by
 * having one kproc mount the another kprocs /prog namespace.  Inter kproc communication is 
 * implemented using a cache-coherent, lock-free, single reader/writer pipe device.
 *
 * SYSCALLs and the LIBUV EVENT LOOP
 *
 * The node9 process model changes the inferno process model by collapsing the segregation of
 * Progs and Procs down into two Proc variants sharing the same base properties.  Kernel procs
 * are now kproc_t types and "interpreter" procs which are 'vproc_t' types.  
 *
 * Kernel procs can be naked background threads or base threads that support a collection of
 * user VM 'vprocs'.  The vproc_t structure enables the lua fibers to act as independent
 * processes.   The kernel space is protected by creating a lua sandbox and by other security
 * features within the plan9/inferno model.
 *
 * Styx syscalls are initiated by creating a request packet and passing it as a baton
 * into a libuv worker thread.  Syscalls can be initiated by both kprocs and vprocs.
 *
 * Normally the base kernel proc makes a scheduling pass through the lua fibers which perform
 * normal computations and/or execute styx syscalls.  The syscalls are created and usually initiate
 * a libuv worker thread which initiates libuv i/o and event requests for later loop processing.
 * This technique allows the lua/luv scheduler to deschedule the lua vproc while
 * the syscall is executing.  The rest of the ready lua processes are then given a chance to 
 * execute.  When all the ready lua vprocs have been serviced, the kernel continues as a kproc_t
 * and handles the queued syscall requests which includes rescheduling any lua vprocs waiting for
 * I/O and syscall request completion.
 *
 * After the libuv event pass, the lua scheduler begins again executing ready vprocs and the
 * process continues until the base kernel proc is terminated.
 *
 * SYSCALL, STYX DEVICES and KERNEL SEPARATION
 * 
 * Styx/node9 channel and device operations are normally implemented within the syscall worker
 * threads which result in low-level timer, file system and network device requests.  These are
 * handled through the portable libuv async operations.  User syscalls are mediated below the 
 * interpreter inteface using the vproc_t shadow process. The vproc_t acts as a proxy for the 
 * user process within the kernel.  Node9 follows this model all the way down to the lower-level
 * channel and device operations.  Ultimately styx services at the device layer initiate asynchronous
 * libuv requests to complete the operation.  
 * 
 * Synchronization at this layer happens in three ways.  The first method is the standard 
 * exclusion mutexes required to protect the integrity of user process and kernel data structures.
 * The second is the alternating request / completion cycle of the user processes and the 
 * kernel proc which handles many sys requests.  
 * 
 * The third is a variation of this which is used when the old plan9/inferno kernel needed 
 * to guarantee the serialization of long-running operations.  Inferno used a queued i/o
 * handler which ultimately used it's rendezvous RPC and associated locking model.  Since
 * we use an event loop and callbacks, the queued I/O operations are unrolled into libuv
 * uv_async_send mechanism.  Queued I/O operations are sent by the worker thread to the 
 * libuv queue listener via uv_async_send.  When the kernel sweeps through the event loop
 * these async signals are handled synchronously in the order received.
 *
 * SYSTEM CALLS
 *
 * The internel kernel calls are made available through a set of syscall "listners" in 
 * the kernel thread that are activated by libuv uv_async_send calls in the syscall code.
 * The uv_async_send calls emulate the syscall software interrupt mechanism in a native
 * operating system implementation.  The syscalls can be invoked anywhere in the the user
 * or kernel space.  
 *
 * The syscall listeners are initialized at boot time.  
 *
 * Each syscall passes two elements through the generic syscall message structure.  The first 
 * element is a pointer to the syscall invoker (proc_t*).  The second element is a structure
 * which describes the syscall itself and contains call parameters specific to the call.
 * An optional third field is nil if unused or it may contain the address of a custom callback
 * procedure.
 *
 * By default the kernel uses the proc_t* process type to determine what to do on syscall
 * completion.  If it's an lua/luv interpreter process, the syscall listener will pass
 * the result values or error state back to the luv fiber held in wait state.  Once the
 * values are placed onto the luv fibers stack, the kernel places the fiber in the ready queue.
 * 
 * If the invoker is a kernel process (kproc or hproc) it will execute a general demarshalling callback
 * appropriate for the process.  Any of these can be overridden by the optional callback.
 * The current kernel system calls are:
 *
 * Sys_open: open a file specified by path and return a file descriptor
 * Sys_seek: seek to a location on a file descriptor
 * Sys_create: create a new file specified by path
 * Sys_dup: duplicate a file descriptor
 * Sys_read: read at most 'n' bytes from file into a buffer
 * Sys_readn: read exactly 'n' bytes from a file into a buffer
 * Sys_pread: read at most 'n' bytes from file into buffer without changing offset
 * Sys_dirread: read directory entries from directory specified by file descriptor
 * Sys_write: write exactly 'n' bytes of data from buffer into file.
 * Sys_pwrite: write exactly 'n' bytes of data from buffer into file with changing offset
 * Sys_print: format and print utf string to stdout
 * Sys_fprint: format and print utf string to file descriptor
 * Sys_werrstr: set the system error string for the current process
 * Sys_stat: read the file information from the file in path string
 * Sys_fstat: read the file information from the file specified in descriptor
 * Sys_wstat: write the file information to the file in path string
 * Sys_fwstat: write the file information to the file in file descriptor
 * Sys_iounit: return the maximum size atomic i/o operation for the file descriptor
 * Sys_bind: bind specified path or device to location specified in target.
 * Sys_mount: bind specified remote path to location specified in target
 * Sys_unmount: unmount previous mount
 * Sys_remove: remove namespace target specified in path
 * Sys_chdir: move to location in current namespace changing '.' 
 * Sys_filedes: accepts an integer handle and returns a new file descriptor object
 * Sys_fd2path: return the path associated with the file descriptor object
 * Sys_file2chan: creates a file channel in service directory 'dir' to serve information
 * Sys_pipe: create a pipe object with endpoints opened for R/W from the pipe device.
 * Sys_stream: stream copy src file to dst file until either read or write fails. return num bytes copied.
 * Sys_dial: create an outgoing connection object for the specified network path
 * Sys_announce: announce that caller is interested in a specific connection type
 * Sys_listen: listen for incoming data on an announced endpoint
 * Sys_export: export part of the namespace to an external client
 * Sys_millisec: return the value of the system millisecond clock
 * Sys_sleep: suspend the current process for <period> milliseconds
 * Sys_fversion: manually perform a styx version negotiation on connection (rare)
 * Sys_fauth: open an authentication channel on the file descriptor to execute auth protocol
 * Sys_pctl: change the current process sharing attributes for file group, namespace group, devices etc
 * 
 */
 
// extern	int	srvf2c(char*, char*, Sys_FileIO*);

/*
 * System types connected to gc
 */
//uchar	FDmap[] = Sys_FD_map;
//uchar	FileIOmap[] = Sys_FileIO_map;
//void	freeFD(Heap*, int);
//void	freeFileIO(Heap*, int);
//Type*	TFD;
//Type*	TFileIO;

//static	uchar	rmap[] = Sys_FileIO_read_map;
//static	uchar	wmap[] = Sys_FileIO_write_map;
//static	Type*	FioTread;
//static	Type*	FioTwrite;
//static	uchar	dmap[] = Sys_Dir_map;
//static	Type*	Tdir;


/* sys module initialization */
/*void
sysinit(void)
{
	//  initialize fid and tag maps if necessary
    printf("sys:init initializing syscall module\n");
    
	// Support for devsrv.c 
	printf("sys:init initializing devsrv read/write buffers\n");

	// Support for dirread
	printf("sys:init initializing dirread\n");
}
*/

/*
void
freeFileIO(Heap *h, int swept)
{
	Sys_FileIO *fio;

	if(swept)
		return;

	fio = H2D(Sys_FileIO*, h);
	destroy(fio->read);
	destroy(fio->write);
}
*/

FD* 
pushchan(luv_state_t* self, int fd)
{
    // USE THE "struct FD" here to create the node9_chan_t
    // pretty simple.  Use the fdtochan to pull up the channel
    // within the NODE9_CHAN_T object
    lua_State *L = self->L;
    FD* new_fd;
    
    // store the channel pointer into the NODE9_CHAN_T object metatable
    // and leave the metatable object on the stack for the user to store and use
    new_fd = (FD*)lua_newuserdata(L, sizeof(FD));
    luaL_getmetatable(L, NODE9_CHAN_T);
    lua_setmetatable(L, -2);
    
    // store the fd and group
    new_fd->fd = fd;
    new_fd->grp = up->env->fgrp;
    // save a reference to the associated channel
    // dont forget to unref on release
    new_fd->c = fdtochan(new_fd->grp, fd, -1, 0, 1);
    // we're using it
    incref(&(up->env->fgrp->r));
    
    return new_fd;
}


#define fdchk(x)	((x) == (Sys_FD*)H ? -1 : (x)->fd)

void
seterror(char *err, ...)
{
	char *estr;
	va_list arg;

	estr = up->env->errstr;
	va_start(arg, err);
	vseprint(estr, estr+ERRMAX, err, arg);
	va_end(arg);
}


char*
syserr(char *s, char *es)
{
	Osenv *o;

	o = up->env;
	kstrcpy(s, o->errstr, es - s);
	return s + strlen(s);
}


/****************************** SYSTEM CALLS ***************************************
 *
 * All syscalls are executed by an available thread from the worker pool.  At the start
 * of all system calls you need to invoke the SYSCALL_BEGIN(calltype, work ref) macro. 
 * This will define and initialize the syscall pointer so you can access the syscall
 * parameters.  This also gives you access to extra syscall fields (calling proc and 
 * interpreter state, if any).  The SYSCALL_BEGIN macro will also set the thread-local
 * "up" value to the calling proc so that any invoked kernel calls will refer to the
 * proper process context.
 *
 * Any "after_work" callbacks specified are guaranteed to execute in the event loop
 * thread, asynchronously and after syscall worker completion or cancellation. The 
 * callback will be executed in at least the next full sweep of the event loop. Though
 * the after work callback receives the original request, bear in mind that you are
 * now running in the event loop thread itself and "up" points to the hosting kernel 
 * proc.  Also, any blocking function calls you make here *will* block the event
 * loop, so mutexes and kernel calls are highly discouraged.  The after work callback
 * is however well suited to syscall/event-loop synchronization.
 *
 * If you need to refer to the original reqeusting proc in the "after callback",
 * use the SYSCALL_AFTER(calltype, work ref) macro to define, cast and initialize 
 * the syscall pointer.  The original requesting proc will be in syscall->proc, but
 * make sure you check it for nil as the syscall may have destroyed the calling 
 * proc.  
 * 
 * SYSCALL_AFTER *does not* set the thread-local "up" value for obvious reasons.
 * If you absolutely must make a non-blocking kernel call, see if you can't simply pass
 * syscall->proc manually.   If the kernel call needs the value of "up", make sure
 * you save and restore the thread-local up value before and after any such calls
 * by using the uv_key_get and uv_key_set respectively.
 *
 ***********************************************************************************/


/* Sys_open: Issues a kernel call to open a channel given a path and mode.  If
 * successful, a client channel userdata is created and entered into the metatable 
 * and returned on the stack.  If it fails, nil is returned on stack.  If async I/O
 * is cancelled then error is indicated.
 */

// executed in the context of the vproc_t in a worker thread
void
Sys_open(uv_work_t* req)
{
	int fd;
    
    // set process context to syscall
    SYSCALL_BEGIN(F_Sys_open, req);

    // do the kernel call
    fd = kopen(syscall->path, syscall->mode);

    // for universal syscalls (kernel or user space) we should store the result in the req
    // and allow the callback requester to specify the completion function.  One completion function
    // would push the result onto the lua stack.  another one could simply return the value to an 
    // async kernel function.  until then we just do the lua version
    
    // if it worked, store the file descriptor as a ref to the kernel channel in the metatable
    if (fd != -1) {
        // push the chan descr for up, current state and number onto the requesters lua stack so they can save it
        pushchan(syscall->state, fd);
        
        // at this point the new userdata channel should be on the 
        // stack of the suspended luv state
    }
    else {
        // it didn't work, just return nil. last error is set by kernel
        lua_pushnil(syscall->state->L);
    }
    
    // release the request path
    free(syscall->path);
}


/* dirread reads the directory entries from an open directory file
 * descriptor and returns them in a table array of the following form:
 *    (n, <Dir0>, <Dir1> .. <Dir(n-1)>)
 * 
 * Where 'n' is the number of entries in the table and dir(0) .. dir(n-1)
 * are directory entries of the form returned by the stat call.  
 *
 * To retrieve all directory entries, the requester should call dirread until
 * 'n' is equal to zero.  
 *
 * If 'n' is less than zero, an error has occurrred and the kernel will have
 * set the respective error value in the error buffer.
 *
 * NOTE: A more lua-like implementation would simply return sucessive tables
 * and the EOF would be indicated by a zero size table or nil.  Unfortunately
 * this precludes an error indicator -- short of raising an exception.
 */

void
Sys_dirread(uv_req_t* req)
{
    Dir *b;
    int i, n;
    int tsize;
    uchar *d;

    SYSCALL_BEGIN(F_Sys_dirread, req);

    n = kdirread(syscall->fd->fd, &b);

    // set array size
    asize = n<=0? 2: n+1;
    
    // build return table
    lua_createtable(L, asize, 0);

    // first entry is the number of results or an error
    lua_pushinteger(L, n);
    lua_rawseti (L, -2, 1);
    
    // if end of stream or error, just finish table
    if(n <= 0) {
        lua_pushnil(L);
        lua_rawseti(L, -2, 1);
    }
    else {
        for(i = 0; i < n; i++) {
            unpackdir(b+i, (Sys_Dir*)d);
            d += Sys_Dir_size;
            new_dirent = (Dir*)lua_newuserdata(L, sizeof(Dir));
            lua_pushudata(L, new_dirent);
            lua_rawseti (L, -2, i);
        }
    }
    // release dir buffer
    free(b);
}

// executed in the context of the vproc_t in a worker thread
void
Sys_freeFD(uv_work_t* req)
{
	int fd;
    FD* dsc;
    
    // set syscall context
    SYSCALL_BEGIN(F_Sys_freeFD, req);
    
    // descriptor
    dsc = syscall->fd;
        
    // free the descriptor
	if(dsc->fd >= 0) {
        // close the fd associated with this fgrp
        kfgrpclose(dsc->grp, dsc->fd);
    }
    // close the fgrp belonging to the proc if necessary
	closefgrp(dsc->grp);

}

// executed in the context of the hproc_t in the event loop thread
void 
Sys_req_complete(uv_work_t* req, int status)
{
    
    // set the context
    SYSCALL_AFTER(F_Sys_call,req);
    
    if (status == -1) {
        // the request was cancelled, just return nil and set last error
        lua_pushnil(syscall->state->L);

        // the closest inferno error is "interrupted"
        seterror(Eintr);
    }

    // re-activate requesting luv fiber
    luvL_state_ready(syscall->state);

    // release the request
    free(syscall);

}


/*
void
Sys_pipe(void *fp)
{
	Array *a;
	int fd[2];
	Sys_FD **sfd;
	F_Sys_pipe *f;

	f = fp;
	*f->ret = -1;

	a = f->fds;
	if(a->len < 2)
		return;
	if(kpipe(fd) < 0)
		return;

	sfd = (Sys_FD**)a->data;
	destroy(sfd[0]);
	destroy(sfd[1]);
	sfd[0] = H;
	sfd[1] = H;
	sfd[0] = mkfd(fd[0]);
	sfd[1] = mkfd(fd[1]);
	*f->ret = 0;
}

void
Sys_fildes(void *fp)
{
	F_Sys_fildes *f;
	int fd;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;
	release();
	fd = kdup(f->fd, -1);
	acquire();
	if(fd == -1)
		return;
	*f->ret = mkfd(fd);
}

void
Sys_dup(void *fp)
{
	F_Sys_dup *f;

	f = fp;
	release();
	*f->ret = kdup(f->old, f->new);	
	acquire();
}

void
Sys_create(void *fp)
{
	int fd;
	F_Sys_create *f;

	f = fp;
	destroy(*f->ret);
	*f->ret = H;
	release();
	fd = kcreate(string2c(f->s), f->mode, f->perm);
	acquire();
	if(fd == -1)
		return;

	*f->ret = mkfd(fd);
}

void
Sys_remove(void *fp)
{
	F_Sys_remove *f;

	f = fp;
	release();
	*f->ret = kremove(string2c(f->s));
	acquire();
}

void
Sys_seek(void *fp)
{
	F_Sys_seek *f;

	f = fp;
	release();
	*f->ret = kseek(fdchk(f->fd), f->off, f->start);
	acquire();
}

void
Sys_unmount(void *fp)
{
	F_Sys_unmount *f;

	f = fp;
	release();
	*f->ret = kunmount(string2c(f->s1), string2c(f->s2));
	acquire();
}

void
Sys_read(void *fp)
{
	int n;
	F_Sys_read *f;

	f = fp;
	n = f->n;
	if(f->buf == (Array*)H || n < 0) {
		*f->ret = 0;
		return;		
	}
	if(n > f->buf->len)
		n = f->buf->len;

	release();
	*f->ret = kread(fdchk(f->fd), f->buf->data, n);
	acquire();
}

void
Sys_readn(void *fp)
{
	int fd, m, n, t;
	F_Sys_readn *f;

	f = fp;
	n = f->n;
	if(f->buf == (Array*)H || n < 0) {
		*f->ret = 0;
		return;		
	}
	if(n > f->buf->len)
		n = f->buf->len;
	fd = fdchk(f->fd);

	release();
	for(t = 0; t < n; t += m){
		m = kread(fd, (char*)f->buf->data+t, n-t);
		if(m <= 0){
			if(t == 0)
				t = m;
			break;
		}
	}
	*f->ret = t;
	acquire();
}

void
Sys_pread(void *fp)
{
	int n;
	F_Sys_pread *f;

	f = fp;
	n = f->n;
	if(f->buf == (Array*)H || n < 0) {
		*f->ret = 0;
		return;		
	}
	if(n > f->buf->len)
		n = f->buf->len;

	release();
	*f->ret = kpread(fdchk(f->fd), f->buf->data, n, f->off);
	acquire();
}

void
Sys_chdir(void *fp)
{
	F_Sys_chdir *f;

	f = fp;
	release();
	*f->ret = kchdir(string2c(f->path));
	acquire();
}

void
Sys_write(void *fp)
{
	int n;
	F_Sys_write *f;

	f = fp;
	n = f->n;
	if(f->buf == (Array*)H || n < 0) {
		*f->ret = 0;
		return;		
	}
	if(n > f->buf->len)
		n = f->buf->len;

	release();
	*f->ret = kwrite(fdchk(f->fd), f->buf->data, n);
	acquire();
}

void
Sys_pwrite(void *fp)
{
	int n;
	F_Sys_pwrite *f;

	f = fp;
	n = f->n;
	if(f->buf == (Array*)H || n < 0) {
		*f->ret = 0;
		return;		
	}
	if(n > f->buf->len)
		n = f->buf->len;

	release();
	*f->ret = kpwrite(fdchk(f->fd), f->buf->data, n, f->off);
	acquire();
}
*/

static void
unpackdir(Dir *d, Sys_Dir *sd)
{
	retstr(d->name, &sd->name);
	retstr(d->uid, &sd->uid);
	retstr(d->gid, &sd->gid);
	retstr(d->muid, &sd->muid);
	sd->qid.path = d->qid.path;
	sd->qid.vers = d->qid.vers;
	sd->qid.qtype = d->qid.type;
	sd->mode = d->mode;
	sd->atime = d->atime;
	sd->mtime = d->mtime;
	sd->length = d->length;
	sd->dtype = d->type;
	sd->dev = d->dev;
}

/*
static Dir*
packdir(Sys_Dir *sd)
{
	char *nm[4], *p;
	int i, n;
	Dir *d;

	nm[0] = string2c(sd->name);
	nm[1] = string2c(sd->uid);
	nm[2] = string2c(sd->gid);
	nm[3] = string2c(sd->muid);
	n = 0;
	for(i=0; i<4; i++)
		n += strlen(nm[i])+1;
	d = smalloc(sizeof(*d)+n);
	p = (char*)d+sizeof(*d);
	for(i=0; i<4; i++){
		n = strlen(nm[i])+1;
		memmove(p, nm[i], n);
		nm[i] = p;
		p += n;
	}
	d->name = nm[0];
	d->uid = nm[1];
	d->gid = nm[2];
	d->muid = nm[3];
	d->qid.path = sd->qid.path;
	d->qid.vers = sd->qid.vers;
	d->qid.type = sd->qid.qtype;
	d->mode = sd->mode;
	d->atime = sd->atime;
	d->mtime = sd->mtime;
	d->length = sd->length;
	d->type = sd->dtype;
	d->dev = sd->dev;
	return d;
}

void
Sys_fstat(void *fp)
{
	Dir *d;
	F_Sys_fstat *f;

	f = fp;
	f->ret->t0 = -1;
	release();
	d = kdirfstat(fdchk(f->fd));
	acquire();
	if(d == nil)
		return;
	if(waserror() == 0){
		unpackdir(d, &f->ret->t1);
		f->ret->t0 = 0;
		poperror();
	}
	free(d);
}

void
Sys_stat(void *fp)
{
	Dir *d;
	F_Sys_stat *f;

	f = fp;
	f->ret->t0 = -1;
	release();
	d = kdirstat(string2c(f->s));
	acquire();
	if(d == nil)
		return;
	if(waserror() == 0){
		unpackdir(d, &f->ret->t1);
		f->ret->t0 = 0;
		poperror();
	}
	free(d);
}

void
Sys_fd2path(void *fp)
{
	F_Sys_fd2path *f;
	char *s;
	void *r;

	f = fp;
	r = *f->ret;
	*f->ret = H;
	destroy(r);
	release();
	s = kfd2path(fdchk(f->fd));
	acquire();
	if(waserror() == 0){
		retstr(s, f->ret);
		poperror();
	}
	free(s);
}

void
Sys_mount(void *fp)
{
	F_Sys_mount *f;

	f = fp;
	release();
	*f->ret = kmount(fdchk(f->fd), fdchk(f->afd), string2c(f->on), f->flags, string2c(f->spec));
	acquire();
}

void
Sys_bind(void *fp)
{
	F_Sys_bind *f;

	f = fp;
	release();
	*f->ret = kbind(string2c(f->s), string2c(f->on), f->flags);
	acquire();
}

void
Sys_wstat(void *fp)
{
	Dir *d;
	F_Sys_wstat *f;

	f = fp;
	d = packdir(&f->d);
	release();
	*f->ret = kdirwstat(string2c(f->s), d);
	acquire();
	free(d);
}

void
Sys_fwstat(void *fp)
{
	Dir *d;
	F_Sys_fwstat *f;

	f = fp;
	d = packdir(&f->d);
	release();
	*f->ret = kdirfwstat(fdchk(f->fd), d);
	acquire();
	free(d);
}

void
Sys_print(void *fp)
{
	int n;
	Prog *p;
	Chan *c;
	char buf[1024], *b = buf;
	F_Sys_print *f;
	f = fp;
	c = up->env->fgrp->fd[1];
	if(c == nil)
		return;
	p = currun();

	release();
	n = xprint(p, f, &f->vargs, f->s, buf, sizeof(buf));
	if (n >= sizeof(buf)-UTFmax-2)
		n = bigxprint(p, f, &f->vargs, f->s, &b, sizeof(buf));
	*f->ret = kwrite(1, b, n);
	if (b != buf)
		free(b);
	acquire();
}

void
Sys_fprint(void *fp)
{
	int n;
	Prog *p;
	char buf[1024], *b = buf;
	F_Sys_fprint *f;

	f = fp;
	p = currun();
	release();
	n = xprint(p, f, &f->vargs, f->s, buf, sizeof(buf));
	if (n >= sizeof(buf)-UTFmax-2)
		n = bigxprint(p, f, &f->vargs, f->s, &b, sizeof(buf));
	*f->ret = kwrite(fdchk(f->fd), b, n);
	if (b != buf)
		free(b);
	acquire();
}

void
Sys_werrstr(void *fp)
{
	F_Sys_werrstr *f;

	f = fp;
	*f->ret = 0;
	kstrcpy(up->env->errstr, string2c(f->s), ERRMAX);
}

void
Sys_dial(void *fp)
{
	int cfd;
	char dir[NETPATHLEN], *a, *l;
	F_Sys_dial *f;

	f = fp;
	a = string2c(f->addr);
	l = string2c(f->local);
	release();
	f->ret->t0 = kdial(a, l, dir, &cfd);
	acquire();
	destroy(f->ret->t1.dfd);
	f->ret->t1.dfd = H;
	destroy(f->ret->t1.cfd);
	f->ret->t1.cfd = H;
	if(f->ret->t0 == -1)
		return;

	f->ret->t1.dfd = mkfd(f->ret->t0);
	f->ret->t0 = 0;
	f->ret->t1.cfd = mkfd(cfd);
	retstr(dir, &f->ret->t1.dir);
}

void
Sys_announce(void *fp)
{
	char dir[NETPATHLEN], *a;
	F_Sys_announce *f;

	f = fp;
	a = string2c(f->addr);
	release();
	f->ret->t0 = kannounce(a, dir);
	acquire();
	destroy(f->ret->t1.dfd);
	f->ret->t1.dfd = H;
	destroy(f->ret->t1.cfd);
	f->ret->t1.cfd = H;
	if(f->ret->t0 == -1)
		return;

	f->ret->t1.cfd = mkfd(f->ret->t0);
	f->ret->t0 = 0;
	retstr(dir, &f->ret->t1.dir);
}

void
Sys_listen(void *fp)
{
	F_Sys_listen *f;
	char dir[NETPATHLEN], *d;

	f = fp;
	d = string2c(f->c.dir);
	release();
	f->ret->t0 = klisten(d, dir);
	acquire();

	destroy(f->ret->t1.dfd);
	f->ret->t1.dfd = H;
	destroy(f->ret->t1.cfd);
	f->ret->t1.cfd = H;
	if(f->ret->t0 == -1)
		return;

	f->ret->t1.cfd = mkfd(f->ret->t0);
	f->ret->t0 = 0;
	retstr(dir, &f->ret->t1.dir);
}

void
Sys_millisec(void *fp)
{
	F_Sys_millisec *f;

	f = fp;
	*f->ret = osmillisec();
}

void
Sys_sleep(void *fp)
{
	F_Sys_sleep *f;

	f = fp;
	release();
	if(f->period > 0){
		if(waserror()){
			acquire();
			error("");
		}
		osenter();
		*f->ret = limbosleep(f->period);
		osleave();
		poperror();
	}
	acquire();
}

void
Sys_stream(void *fp)
{
	Prog *p;
	uchar *buf;
	int src, dst;
	F_Sys_stream *f;
	int nbytes, t, n;

	f = fp;
	buf = malloc(f->bufsiz);
	if(buf == nil) {
		kwerrstr(Enomem);
		*f->ret = -1;
		return;
	}

	src = fdchk(f->src);
	dst = fdchk(f->dst);

	p = currun();

	release();
	t = 0;
	nbytes = 0;
    // while prog is not in killed state
	while(p->kill == nil) {
		n = kread(src, buf+t, f->bufsiz-t);
		if(n <= 0)
			break;
		t += n;
		if(t >= f->bufsiz) {
			if(kwrite(dst, buf, t) != t) {
				t = 0;
				break;
			}

			nbytes += t;
			t = 0;
		}
	}
	if(t != 0) {
		kwrite(dst, buf, t);
		nbytes += t;
	}
	acquire();
	free(buf);
	*f->ret = nbytes;
}

void
Sys_export(void *fp)
{
	F_Sys_export *f;

	f = fp;
	release();
	*f->ret = export(fdchk(f->c), string2c(f->dir), f->flag&Sys_EXPASYNC);
	acquire();
}

void
Sys_file2chan(void *fp)
{
	int r;
	Heap *h;
	Channel *c;
	Sys_FileIO *fio;
	F_Sys_file2chan *f;
	void *sv;

	h = heap(TFileIO);

	fio = H2D(Sys_FileIO*, h);

	c = cnewc(FioTread, movtmp, 16);
	fio->read = c;

	c = cnewc(FioTwrite, movtmp, 16);
	fio->write = c;

	f = fp;
	sv = *f->ret;
	*f->ret = fio;
	destroy(sv);

	release();
	r = srvf2c(string2c(f->dir), string2c(f->file), fio);
	acquire();
	if(r == -1) {
		*f->ret = H;
		destroy(fio);
	}
}

enum
{
	// the following pctl calls can block and must release the virtual machine
	BlockingPctl=	Sys_NEWFD|Sys_FORKFD|Sys_NEWNS|Sys_FORKNS|Sys_NEWENV|Sys_FORKENV
};

void
Sys_pctl(void *fp)
{
	int fd;
	Prog *p;
	List *l;
	Chan *c;
	volatile struct {Pgrp *np;} np;
	Pgrp *opg;
	Chan *dot;
	Osenv *o;
	F_Sys_pctl *f;
	Fgrp *fg, *ofg, *nfg;
	volatile struct {Egrp *ne;} ne;
	Egrp *oe;

	f = fp;

	p = currun();
	if(f->flags & BlockingPctl)
		release();

	np.np = nil;
	ne.ne = nil;
	if(waserror()) {
		closepgrp(np.np);
		closeegrp(ne.ne);
		if(f->flags & BlockingPctl)
			acquire();
		*f->ret = -1;
		return;
	}

	o = p->osenv;
	if(f->flags & Sys_NEWFD) {
		ofg = o->fgrp;
		nfg = newfgrp(ofg);
		lock(&ofg->l);
		// file descriptors to preserve
		for(l = f->movefd; l != H; l = l->tail) {
			fd = *(int*)l->data;
			if(fd >= 0 && fd <= ofg->maxfd) {
				c = ofg->fd[fd];
				if(c != nil && fd < nfg->nfd && nfg->fd[fd] == nil) {
					incref(&c->r);
					nfg->fd[fd] = c;
					if(nfg->maxfd < fd)
						nfg->maxfd = fd;
				}
			}
		}
		unlock(&ofg->l);
		o->fgrp = nfg;
		closefgrp(ofg);
	}
	else
	if(f->flags & Sys_FORKFD) {
		ofg = o->fgrp;
		fg = dupfgrp(ofg);
		// file descriptors to close 
		for(l = f->movefd; l != H; l = l->tail)
			kclose(*(int*)l->data);
		o->fgrp = fg;
		closefgrp(ofg);
	}

	if(f->flags & Sys_NEWNS) {
		np.np = newpgrp();
		dot = o->pgrp->dot;
		np.np->dot = cclone(dot);
		np.np->slash = cclone(dot);
		cnameclose(np.np->slash->name);
		np.np->slash->name = newcname("/");
		np.np->nodevs = o->pgrp->nodevs;
		opg = o->pgrp;
		o->pgrp = np.np;
		np.np = nil;
		closepgrp(opg);
	}
	else
	if(f->flags & Sys_FORKNS) {
		np.np = newpgrp();
		pgrpcpy(np.np, o->pgrp);
		opg = o->pgrp;
		o->pgrp = np.np;
		np.np = nil;
		closepgrp(opg);
	}

	if(f->flags & Sys_NEWENV) {
		oe = o->egrp;
		o->egrp = newegrp();
		closeegrp(oe);
	}
	else
	if(f->flags & Sys_FORKENV) {
		ne.ne = newegrp();
		egrpcpy(ne.ne, o->egrp);
		oe = o->egrp;
		o->egrp = ne.ne;
		ne.ne = nil;
		closeegrp(oe);
	}

	if(f->flags & Sys_NEWPGRP)
		newgrp(p);

	if(f->flags & Sys_NODEVS)
		o->pgrp->nodevs = 1;

	poperror();

	if(f->flags & BlockingPctl)
		acquire();

	*f->ret = p->pid;
}


void
Sys_fauth(void *fp)
{
	int fd;
	F_Sys_fauth *f;
	void *r;

	f = fp;
	r = *f->ret;
	*f->ret = H;
	destroy(r);
	release();
	fd = kfauth(fdchk(f->fd), string2c(f->aname));
	acquire();
	if(fd >= 0)
		*f->ret = mkfd(fd);
}

void
Sys_fversion(void *fp)
{
	void *r;
	F_Sys_fversion *f;
	int n;
	char buf[20], *s;

	f = fp;
	f->ret->t0 = -1;
	r = f->ret->t1;
	f->ret->t1 = H;
	destroy(r);
	s = string2c(f->version);
	n = strlen(s);
	if(n >= sizeof(buf)-1)
		n = sizeof(buf)-1;
	memmove(buf, s, n);
	buf[n] = 0;
	release();
	n = kfversion(fdchk(f->fd), f->msize, buf, sizeof(buf));
	acquire();
	if(n >= 0){
		f->ret->t0 = f->msize;
		retnstr(buf, n, &f->ret->t1);
	}
}

void
Sys_iounit(void *fp)
{
	F_Sys_iounit *f;

	f = fp;
	release();
	*f->ret = kiounit(fdchk(f->fd));
	acquire();
}

void
ccom(Progq **cl, Prog *p)
{
	volatile struct {Progq **cl;} vcl;

	cqadd(cl, p);
	vcl.cl = cl;
	if(waserror()) {
        // no killcomm
		if(p->ptr != nil) {
			cqdelp(vcl.cl, p);
			p->ptr = nil;
		}
		nexterror();
	}
	cblock(p);
	poperror();
}

void
crecv(Channel *c, void *ip)
{
	Prog *p;
	REG rsav;

	if(c->send->prog == nil && c->size == 0) {
		p = currun();
		p->ptr = ip;
		ccom(&c->recv, p);
		return;
	}

	rsav = R;
	R.s = &c;
	R.d = ip;
	irecv();
	R = rsav;
}

void
csend(Channel *c, void *ip)
{
 	Prog *p;
	REG rsav;

	if(c->recv->prog == nil && (c->buf == H || c->size == c->buf->len)) {
		p = currun();
		p->ptr = ip;
		ccom(&c->send, p);
		return;
	}

	rsav = R;
	R.s = ip;
	R.d = &c;
	isend();
	R = rsav;
}
*/
