------------------------------------------------------------------------------
--
-- node9 scheduler
--
------------------------------------------------------------------------------ 

-- foreign function interface
local ffi = require('ffi')
local bit = require('bit')
band = bit.band;
bor = bit.bor
brshift = bit.rshift


function load_cdef(hdr)
    local header = io.open(hdr, "rb")
    local cdefs = header:read("*all")
    header:close()
    ffi.cdef(cdefs)
end

-- load the headers, cdefs and prototypes
ffi.cdef[[
typedef void uv_work_t;
]]
load_cdef("fs/module/ninevals.h")
load_cdef("fs/module/kern.h")
load_cdef("fs/module/node9.h")
load_cdef("fs/module/syscalls.h")

-- load the system constants into our namespace.  ugly: find solution --
sysconst = {}
sc = io.open("fs/module/sysconst.h")
while true do
    local s = sc:read("*line")
    if not s then break end
    local name,val = s:match("Sys_(%a+)%s*=%s*([%w%d\"\']+)")
    if name then
        if val:sub(1,2) == "0x" then
            sysconst[name] = tonumber(val,16)
        elseif val:sub(1,1) == '"' or val:sub(1,1) == "'" then
            sysconst[name] = val:sub(2,#val-1)
        else
            sysconst[name] = tonumber(val)
        end
    end
end
sc:close()

-- mode string generator --
local mtab = { "---", "--x", "-w-", "-wx", "r--",  "r-x", "rw-", "rwx" }

function modes(mode)
    if band(mode,sysconst.DMDIR) ~= 0 then
        s = "d"
    elseif band(mode,sysconst.DMAPPEND) ~= 0 then
        s = "a"
    elseif band(mode,sysconst.DMAUTH) ~= 0 then
        s = "A"
    else
        s = "-"
    end
    
    if band(mode, sysconst.DMEXCL) ~=0 then
        s = s .. "l"
    else
        s = s .. "-"
    end
    s = s .. mtab[band(brshift(mode,6),7)+1] .. mtab[band(brshift(mode,3),7)+1] .. mtab[band(mode,7)+1]
    return s
end

----- CDEF metamethods ------
fdes_mt = {
    __tostring =
        function(fdes)
            local fd = 0 
            if fdes == nil then 
                fd = -1
            else
                fd = fdes.fd
            end
            return string.format("<fildes>: %d",fd)
        end,
}
    
Filedes_m = ffi.metatype("Sys_FD",fdes_mt)

dir_mt = {
    __tostring =
        function(dir)
            return string.format("%s %12s %12s %12d   %16s %s",
                                  modes(tonumber(dir.mode)),
                                  ffi.string(dir.uid),
                                  ffi.string(dir.gid),
                                  tonumber(dir.length),
                                  date(tonumber(dir.atime)),
                                  ffi.string(dir.name))
        end,
}

Dir_m = ffi.metatype("struct Dir",dir_mt)

dirpack_mt = {
    __tostring =
        function(dpack)
            return string.format("<dirpack>: len %d",dpack.num)
        end,
}

Dirpack_m = ffi.metatype("Dirpack",dirpack_mt)
    
-- bind to libnode9 shared library
local node9 = ffi.load('node9')

-- misc utility functions
function mkcstr(s)
    return ffi.new("char [?]", #s+1, s)
end

function cpycstr(s)
    local s = ffi.string(s)
    newstr = ffi.new("char [?]", #s+1, s)
end

function dump_procs()
    print("-----------proc table--------------")
    for i,v in pairs(procs) do
        print("proc key",i,"proc",v)
    end
    print("")
end

function date(otime)
    return os.date("%c",otime)
end

--- node9 object prototypes ---
stat = {}

function stat.new(...)
    args = {...}
    self = {}
    self.name = ""
    self.uid = ""
    self.gid = ""
    self.muid = ""
    if not args[1] then        
        self.qid = {path = ffi.new("uint64_t"), vers = 0, qtype = 0}
        self.mode = 0
        self.atime = 0
        self.mtime = 0
        self.length = ffi.new("int64_t")
        self.dtype = 0
        self.dev = 0
    else
        self.qid = {path = ffi.new("uint64_t") -1, vers = -1, qtype = -1}
        self.mode = -1
        self.atime = -1
        self.mtime = -1
        self.length = ffi.new("int64_t") - 1
        self.dtype = -1
        self.dev = -1
    end
    
    function self.idtuple()
        return self.name, self.uid, self.gid, self.muid
    end
    
    setmetatable(self,
        { __tostring = 
            function(dstat) 
                return string.format("<dirstat>: name: %s, len: %s, uid: %s, gid: %s, mtime: %s", 
                    dstat.name, dstat.length, dstat.uid, dstat.gid, date(dstat.mtime))
            end
        }
    )
                    
    return self
end



-- bring in sheduler
procs = {}


-- SCHEDULER
sched = {}

function sched.new()
    self = {}

    -- scheduler queues
    local rdyq = {}
    local runq = {}
    
    -- resumes proc coroutine and handles exiting processes 
    -- returns true (or gen output) if proc still running or
    -- false if proc has exited
    function resume(proc)
        local xeq, gen = coroutine.resume(proc.co)
        --io.write("node9/sched: exited proc: xeq: ",xeq,", gen: '",gen,"'"); io.flush()
        if xeq == false then
            print(string.format("node9/sched: proc '%s' cannot continue because '%s'",proc.name,gen))
        end
        -- is task still running?
        if coroutine.status(proc.co) == "dead" then
            -- remove proc from table
            procs[proc.pid] = nil
            -- if 'init' died, begin system shutdown
            if proc == init then
                return false
            end
        else
            -- so it's still running, but waiting for completion or next quanta
            proc.status = "waiting"
            if gen then
                proc.status = "yielded"
                self.ready(proc)
            else
                proc.status = "waiting"
            end
        end
        -- feed generated output up, or just the continuation status
        return gen or xeq
    end
                

    function self.ready(proc)
        rdyq[#rdyq+1] = proc
    end
    
    function self.start()
        
        while true do
            -- make all completed requesters ready
            local count = 0
            
            -- two runnable queues:
                -- all pids in the reply queue and
                -- all procs in the rdy queue
            
            -- first run any proc with a pid in the reply queue            
             while true do
                -- check who the next reply is for
                local wait_pid = node9.sysrep()
                -- empty queue?
                if wait_pid == 0 then break end
                local wait_proc = procs[wait_pid]
                --dump_procs()
                if not wait_proc then
                    -- oops. panic
                    print("node9: non existant caller process for pid",wait_pid)
                    return
                end
                -- resume the proc and exit if no more processes
                if not resume(wait_proc) then 
                    return
                end
            end

            -- make any still-ready procs runnable
            runq = rdyq
            rdyq = {}
            
            -- resume each runnable proc
            for _, proc in pairs(runq) do
                if not resume(proc) then
                    return
                end
            end
                
            -- release anything still in the runq (including old procs)
            runq = nil
            
            -- process new events and come back right away if runnable procs
            node9.svc_events(#rdyq)
            
        end
    end
    
    return self
end

-- make a scheduler
schd = sched.new()

-- PROCESS MODEL
proc = {}

-- create a new proc from the specified function and kernel vproc (with startup args)
function proc.new(fun, vproc, pid, ...)
    -- things accessible directly by the fiber
    local sreq = node9.sysbuf(vproc)
    local self = {}
    self.sys = {}
    
    -- inherit system constants
    setmetatable(self.sys, 
        {__index = 
            function (t, k)
                local scon = sysconst[k]
                if not scon then
                    error("sys: no such call or property: " .. k)
                end
                return scon
            end
        })
    
    -- FFI constants --
    self.sys.nulldir = ffi.new("Sys_Dir", {mode = bit.bnot(0), mtime = bit.bnot(0), atime = bit.bnot(0)} )
    self.sys.zerodir = ffi.new("Sys_Dir")
    
    -- publics
    self.vproc = vproc
    self.pid = pid
    
    -- local attributes and functions not directly accessible to the proc function
    local args = {...} 
    
    --
    -- support functions
    --
    
    -- stat pack/unpack
    
    -- unbundles a kernel dir into a node9 sys_dir (dirstat entity)
    function s_unpack(sdir, kdir)
        sdir.name = ffi.string(kdir.name)
        sdir.uid  = ffi.string(kdir.uid)
        sdir.gid  = ffi.string(kdir.gid)
        sdir.muid = ffi.string(kdir.muid)
        sdir.qid.path = kdir.qid.path
        sdir.qid.vers = kdir.qid.vers
        sdir.qid.qtype = kdir.qid.type  -- really a char
        sdir.mode = kdir.mode
        sdir.atime = kdir.atime
        sdir.mtime = kdir.mtime
        sdir.length = kdir.length
        sdir.dtype = kdir.type
        sdir.dev = kdir.dev
    end
    
    -- called on task startup and before first syscall
    -- just a yield now, but reserve for later housekeeping
    function self.init()
        coroutine.yield(1)
    end
    
    -- i/o buffer functions
    function self.sys.mkBuffer(size)
        local buf = ffi.gc(node9.mkBuffer(size), node9.freeBuffer)
        return buf
    end
    
    --
    -- sys library calls
    --   
    local s_open = sreq.open
    function self.sys.open(path,mode)
        s_open.s = mkcstr(path)
        s_open.mode = mode
        node9.sysreq(vproc, node9.Sys_open)
        coroutine.yield()
        local fd = s_open.ret
        if fd ~= nil then
            return ffi.gc(fd, node9.free_fd)
        else
            return nil
        end
    end
    
    local s_create = sreq.create
    function self.sys.create(path,mode,perm)
        s_create.s = mkcstr(path)
        s_create.mode = mode 
        s_create.perm = perm
        node9.sysreq(vproc, node9.Sys_create)
        coroutine.yield()
        local fd = s_create.ret
        if fd ~= nil then
            return ffi.gc(fd, node9.free_fd)
        else
            return nil
        end
    end
   
    -- sys.dup will create a new file descriptor that refers to a currently
    -- open file.  oldfd is the integer handle of the open descriptor and 
    -- newfd will be the integer handle of the new descriptor if it's in
    -- the valid descriptor range.  
    -- notes:
    --      o if newfd is currently in use, the associated descriptor is
    --        released newfd will refer to the new descriptor.
    --      o if newfd is -1, the first available free integer will be used
    --      o the returned value is the integer handle of the new descriptor
    local s_dup = sreq.dup
    function self.sys.dup(oldfd, newfd)
        s_dup.old = oldfd
        s_dup.new = newfd
        node9.sysreq(vproc, node9.Sys_dup)
        coroutine.yield()
        return s_dup.ret
    end
      
    -- sys.fildes creates a new file descriptor object by duplicating the 
    -- file descriptor with handle 'fd'.  it returns the descriptor object
    -- or nil if creation failed
    local s_fildes = sreq.fildes
    function self.sys.fildes(fdnum)
        s_fildes.fd = fdnum
        node9.sysreq(vproc, node9.Sys_fildes)
        coroutine.yield()
        local fd = s_fildes.ret
        if fd ~= nil then
            return ffi.gc(fd, node9.free_fd)
        else
            return nil
        end
    end
--]]    

    -- sys.seek: seek to the specified location in fd
    --      fd: an open file descriptor object
    --      offset: can be a lua number or signed 64 bit cdata
    --      start: specifies where to seek from and is one of:
    --          sys.SEEKSTART (from beginning of file)
    --          sys.SEEKRELA  (from current location)
    --          sys.SEEKEND   (relative to end of file, usually negative)
    
    local s_seek = sreq.seek
    function self.sys.seek(fd, offset, start)
        s_seek.fd = fd
        s_seek.off = offset
        s_seek.start = start
        node9.sysreq(vproc, node9.Sys_seek)
        coroutine.yield()
        return s_seek.ret
    end
    
    -- returns the largest I/O possible on descriptor fd's channel
    -- without splitting into multiple operations, 0 means undefined
    local s_iounit = sreq.iounit
    function self.sys.iounit(fd)
        s_iounit.fd = fd
        node9.sysreq(vproc, node9.Sys_iounit)
        coroutine.yield()
        return s_iounit.ret
    end
    
    -- accepts fd, preallocated cdef array of unsigned byte
    -- and fills buffer with read data
    -- returns number of bytes read
    local s_read = sreq.read
    function self.sys.read(fd, buf, nbytes)
        s_read.fd = fd
        s_read.buf = buf
        s_read.nbytes = nbytes
        node9.sysreq(vproc, node9.Sys_read)
        coroutine.yield()
        return s_read.ret
    end
    
    local s_readn = sreq.readn
    function self.sys.readn(fd, buf, nbytes)
        s_readn.fd = fd
        s_readn.buf = buf
        s_readn.n = nbytes
        node9.sysreq(vproc, node9.Sys_readn)
        coroutine.yield()
        return s_readn.ret
    end
    
    local s_pread = sreq.pread
    function self.sys.pread(fd, buf, nbytes, offset)
        s_pread.fd = fd
        s_pread.buf = buf
        s_pread.n = nbytes
        s_pread.off = offset
        node9.sysreq(vproc, node9.Sys_pread)
        coroutine.yield()
        return s_pread.ret
    end

    -- write buf to file descriptor fd
    -- entire buffer will be written, unless overridden
    -- by optional length argument
    local s_write = sreq.write
    function self.sys.write(fd, buf, ...)
        local args = {...} -- optional number of bytes to write
        s_write.fd = fd
        s_write.buf = buf
        s_write.nbytes = args[1] or buf.len
        node9.sysreq(vproc, node9.Sys_write)
        coroutine.yield()
        return s_write.ret
    end

    local s_pwrite = sreq.pwrite
    function self.sys.pwrite(fd, buf, nbytes, offset)
        s_pwrite.fd = fd
        s_pwrite.buf = buf
        if nbytes == 0 then
            s_pwrite.n = buf.len
        else
            s_pwrite.n = nbytes
        end
        s_pwrite.off = offset
        node9.sysreq(vproc, node9.Sys_pwrite)
        coroutine.yield()
        return s_pwrite.ret
    end
        
    function self.sys.sprint(fmt, ...)
        return string.format(fmt, ...)
    end
   
    local s_print = sreq.print
    function self.sys.print(fmt, ...)
        local tstr = string.format(fmt, ...)
        local tbuf = mkcstr(tstr)
        s_print.buf = tbuf
        s_print.len = #tstr
        node9.sysreq(vproc, node9.Sys_print)
        coroutine.yield()
        return s_print.ret
    end
 
    local s_fprint = sreq.fprint
    function self.sys.fprint(fd, fmt, ...)
        local tstr = string.format(fmt, ...)
        local tbuf = mkcstr(tstr)
        s_fprint.fd = fd
        s_fprint.buf = tbuf
        s_fprint.len = #tstr
        node9.sysreq(vproc, node9.Sys_fprint)
        coroutine.yield()
        return s_fprint.ret
    end
    
--[[
        
    function self.sys.stream(src, dst, bufsize)
        node9.sys_stream(vproc, src, dst, bufsize)
        local ret = coroutine.yield()
        return ret[0]
    end
]]--

    -- construct a stat template
    function self.sys.nulldir()
        return stat.new(-1)
    end
    
    -- returns the stat results for file path
    -- returns a table {int rc, Sys_dir} 
    -- where: rc = 0 on success, -1 on failure
    -- Sys_Dir is created and populated with appropriate values
    -- on failure Sys_Dir is nil
    local s_stat = sreq.stat
    function self.sys.stat(path)
        s_stat.s = mkcstr(path)
        node9.sysreq(vproc, node9.Sys_stat)
        coroutine.yield()
        local rc = -1
        local newstat = nil
        local kdir = s_stat.ret
        if kdir ~= nil then
            rc = 0
            newstat = stat.new()
            s_unpack(newstat, kdir)
        end
        node9.free_dir(kdir)
        return rc, newstat
    end
   
    local s_fstat = sreq.fstat
    function self.sys.fstat(fd)
        s_fstat.fd = fd
        node9.sysreq(vproc, node9.Sys_fstat)
        coroutine.yield()
        local rc = -1
        local newstat = nil
        local kdir = s_fstat.ret
        if kdir ~= nil then
            rc = 0
            newstat = stat.new()
            s_unpack(newstat, kdir)
        end
        node9.free_dir(kdir)
        return rc, newstat
    end

    local s_wstat = sreq.wstat
    function self.sys.wstat(path, sdir)
        -- (create local refs to prevent deallocation)
        local s_name = mkcstr(sdir.name); local s_uid = mkcstr(sdir.uid); 
        local s_gid =  mkcstr(sdir.gid); local s_muid = mkcstr(sdir.muid)
        -- translate to kernel dir
        local s_path = mkcstr(path)
        local s_kdir = ffi.new("Dir", 
            {
                name = s_name, uid = s_suid, gid = s_gid, muid = s_muid, 
                mode = sdir.mode, mtime = sdir.mtime, atime = sdir.atime,
                qid = { path = sdir.path, vers = sdir.vers, type = sdir.qtype },
                length = sdir.length, type = sdir.dtype, dev = sdir.dev
            }
        )
        s_wstat.s   = s_path
        s_wstat.dir = s_kdir
        node9.sysreq(vproc, node9.Sys_wstat)
        coroutine.yield()
        return s_wstat.ret
    end
    
    local s_fwstat = sreq.fwstat
    function self.sys.fwstat(fd, sdir)
        -- (create local refs to prevent deallocation)
        local s_name = mkcstr(sdir.name); local s_uid = mkcstr(sdir.uid); 
        local s_gid =  mkcstr(sdir.gid); local s_muid = mkcstr(sdir.muid)
        -- translate to kernel dir
        local s_kdir = ffi.new("Dir", 
            {
                name = s_name, uid = s_suid, gid = s_gid, muid = s_muid, 
                mode = sdir.mode, mtime = sdir.mtime, atime = sdir.atime,
                qid = { path = sdir.path, vers = sdir.vers, type = sdir.qtype },
                length = sdir.length, type = sdir.dtype, dev = sdir.dev
            }
        )
        s_fwstat.fd  = fd
        s_fwstat.dir = s_kdir
        node9.sysreq(vproc, node9.Sys_fwstat)
        coroutine.yield()
        return s_fwstat.ret
    end
   
    local s_dirread = sreq.dirread
    function self.sys.dirread(fd)
        s_dirread.fd = fd
        node9.sysreq(vproc, node9.Sys_dirread)
        coroutine.yield()
        return ffi.gc(s_dirread.ret, node9.free_dirpack)
    end
      
    function self.sys.errstr()
        local estr = node9.sys_errstr(vproc)
        if estr ~= nil then 
            return ffi.string(estr)
        else
            return nil
        end
    end
        
    function self.sys.werrstr(errstr)
        local err = mkcstr(errstr)
        node9.sys_werrstr(vproc, err)
        return 0
    end
   
   --[[
    function self.sys.bind(name, old, flags)
        node9.sys_bind(vproc, name, old, flags)
        local ret = coroutine.yield()
        return ret[0]
    end
    
    function self.sys.mount(FD, AFD, oldstring, flags, anamestring)
        node9.sys_mount(vproc, FD, AFD, oldstring, flags, anamestring)
        local ret = coroutine.yield()
        return ret[0]
    end
    
    function self.sys.unmount(namestring, oldstring)
        node9.sys_unmount(vproc, namestring, oldstring)
        local ret = coroutine.yield()
        return ret[0]
    end
]]--    

    local s_remove = sreq.remove
    function self.sys.remove(path)
        local pth = mkcstr(path)
        s_remove.s = pth
        node9.sysreq(vproc, node9.Sys_remove)
        coroutine.yield()
        return s_remove.ret
    end
    
    local s_chdir = sreq.chdir
    function self.sys.chdir(path)
        local pth = mkcstr(path)
        s_chdir.path = pth
        node9.sysreq(vproc, node9.Sys_chdir)
        coroutine.yield()
        return s_chdir.ret
    end
    
    local s_fd2path = sreq.fd2path
    function self.sys.fd2path(fd)
        s_fd2path.fd = fd
        node9.sysreq(vproc, node9.Sys_fd2path)
        coroutine.yield()
        if s_fd2path.ret == nil then
            return ""
        end
        local pstring = ffi.gc(s_fd2path.ret, node9.free_cstring)
        return ffi.string(pstring)
    end
   
--[[
    function self.sys.pipe()
        node9.sys_pipe(pid)
        local ret = coroutine.yield()
        return ret
    end
    
    function self.sys.dial(addrstring, localstring)
        node9.sys_dial(vproc, addrstring, localstring)
        local ret = coroutine.yield()
        return ret
    end
    
    function self.sys.announce(addrstring)
        node9.sys_announce(vproc, addrstring)
        local ret = coroutine.yield()
        return ret
    end
    
    function self.sys.listen(connection)
        node9.sys_listen(vproc, connection)
        local ret = coroutine.yield()
        return ret
    end
    
    function self.sys.file2chan(dirstring, filestring)
        node9.sys_chdir(vproc, dirstring, filestring)
        local ret = coroutine.yield()
        return ret[0]
    end
    
    function self.sys.export(FD, dirstring, flags)
        node9.sys_export(vproc, FD, dirstring, flags)
        local ret = coroutine.yield()
        return ret[0]
    end
--]]    
    function self.sys.millisec()
        return node9.sys_millisec()
    end
    
    function self.sys.sleep(millisecs)
        node9.sys_sleep(vproc, millisecs)   -- non-standard async req
        coroutine.yield()
        return sreq.sleep.ret
    end
--[[    
    function self.sys.fversion(FD, bufsize, versionstring)
        node9.sys_fversion(vproc, FD, bufsize, versionstring)
        local ret = coroutine.yield()
        return ret
    end
    
    function self.sys.fauth(FD, anamestring)
        node9.sys_fauth(vproc, FD, anamestring)
        local ret = coroutine.yield()
        return ret[0]
    end
    
    function self.sys.pctl(flags, movefd_list)
        node9.sys_pctl(vproc, flags, movefd_list)
        local ret = coroutine.yield()
        return ret[0]
    end
]]--

    -- create a new task --
    local s_spawn = sreq.spawn
    function self.sys.spawn(fun, name, ...)
        -- create the kernel vproc
        node9.sysreq(vproc, node9.Sys_spawn)
        coroutine.yield()
        local child_pid = s_spawn.ret 
        local child_vproc = node9.procpid(child_pid)    -- sync call
        -- specify the kernel finalizer for child_vproc
        -- free_vproc runs async, notifies proc group and doesn't block
        ffi.gc(child_vproc, node9.vproc_exit)
        -- create the lua task, run its initializer and make it ready
        local new_proc = proc.new(fun, child_vproc, child_pid, ...)
        new_proc.name = name
        schd.ready(new_proc)
    end
    
    -- TASK INITIALIZATION --
    self.co = coroutine.create(fun)    -- create the task state
    self.status = "running"
    procs[self.pid] = self                 -- place in the proc map (in case they syscall during init)
    coroutine.resume(self.co, self, ...)    -- run the tasks own __init__ code /w startup args
    return self
end

function testfs(s)
    local sys=s
    function cat(path)
        local catf = sys.open(path, sys.OREAD)
        if not catf then
            print("cat: could not open file")
            return
        end
        local dbuf = sys.mkBuffer(512)
        while true do
            local nbytes = sys.read(catf, dbuf, 256)
            if nbytes == 0 then break end
            sys.print("%s",ffi.string(dbuf.data,dbuf.len))
        end
    end

    
    sys.print("\ninit: available devices are:\n")
    cat("/dev/drivers")

    sys.print("\ninit: the current cpu type is:\n")
    cat("/env/cputype")
    
    sys.print("\ninit: on host:\n")
    cat("/env/emuhost")

    -- just use a temp buf
    local bootbuf = sys.mkBuffer(80)
    local bdate = os.date()  --safe?
    ffi.copy(bootbuf.data, bdate)
    -- open the boot env file for write, in  rw-rw--- mode
    local bootenv = sys.create("/env/boottime", sys.OWRITE, tonumber("664",8))
    --print("local bootenv desc is:",bootenv)
    --io.flush()
    sys.write(bootenv, bootbuf, #bdate) 
    
    sys.print("\ninit: kernel boot time was:\n")
    cat("/env/boottime")
    
    -- excercise hosted file system
    
    local stime = sys.millisec()
    sys.print("\n\nsystem timer is now %d\n", stime)
    
    -- make a buffer full of (possibly) random data
    local bbuff = sys.mkBuffer(4096)
    bbuff.len = 4096 -- use the entire uninitialized buffer

    local bootdir = sys.create("/testing/boot", sys.OREAD, bor(sys.DMDIR, tonumber("750",8)))  -- create directory
    if not bootdir then 
        sys.print(" ** could not create directory /testing/boot because: '%s'\n",sys.errstr())
    else
        local bios = sys.create("/testing/boot/openbios", sys.ORDWR, tonumber("664",8))  -- make a new file
        if not bios then
            sys.print(" ** could not create /testing/boot/openbios because: '%s'\n",sys.errstr())
        else
            -- get another handle to the file
            sys.print("duplicating descriptor %d\n",bios.fd)
            local newfd = sys.dup(bios.fd, -1)
            if newfd == -1 then
                sys.print("couldn't duplicate file descriptor\n");
                return
            end
            sys.print("duplicate handle is %d\n",newfd);
            -- get another file descriptor into the file
            local obios = sys.fildes(bios.fd)
            if obios == nil then
                sys.print("couldn't allocate a new file descriptor\n");
                return
            end
            sys.print("new file descriptor handle is %d\n",obios.fd)
            
            local unit = sys.iounit(bios)
            sys.print("maximum i/o unit size on this device is %d\n", sys.iounit(bios))
            
            local n
            -- write 256 megabytes
            for i = 1,256 do
                for j = 1,256 do
                    sys.write(bios, bbuff)
                end
            end
            local ftime = sys.millisec()
            local etime = (ftime - stime) / 1000.0
            local rate = 256 / etime
            sys.print("\n\nsystem timer is now %d\n", ftime)
            sys.print("256MB file write completed in %fs\n",etime)
            sys.print("io (write) speed is %f MB/s\n", rate)
        
            sys.print("\n\n -- read tests --\n");
            -- read and seek tests
            -- here we seek back to start using a lua number and read the whole file
            local fpos = ffi.new("int64_t",0)
            fpos = sys.seek(bios, fpos, sys.SEEKSTART) -- fpos should be a 64 bit boxed int (cdata)
            sys.print("starting read tests at %s\n",fpos);
            stime = sys.millisec()
            for i = 1,256 do
                for j = 1,256 do
                    n = sys.read(bios, bbuff, 4096)
                    if n < 0 then
                        sys.print("file read failed because '%s'\n",sys.errstr())
                        return
                    end
                end
            end
            ftime = sys.millisec()
            etime = (ftime - stime) / 1000.0
            rate = 256 / etime
            sys.print("256MB file read completed in %fs\n",etime)
            sys.print("io (read) speed is %f MB/s\n", rate)
        
            -- now seek 128MB before the end of file and read 
            fpos = fpos + 128*1024*1024  -- get a boxed 128MB value
            fpos = sys.seek(bios, -fpos, sys.SEEKEND)
            sys.print("continuing read tests at end - 128 MB, position is %s\n",fpos)
            stime = sys.millisec()
            for i = 1,128 do
                for j = 1,256 do
                    n = sys.read(bios, bbuff, 4096)
                    if n < 0 then
                        sys.print("file read failed because '%s'\n",sys.errstr())
                        return
                    end
                end
            end
            ftime = sys.millisec()
            etime = (ftime - stime) / 1000.0
            rate = 128 / etime
            sys.print("128MB file read completed in %fs\n",etime)
            sys.print("io (read) speed is %f MB/s\n", rate)
                       
            -- now seek backwards 64MB and read the file
            fpos = fpos / 2
            stime = sys.millisec()
            fpos = sys.seek(bios, -fpos, sys.SEEKRELA)
            sys.print("continuing read tests at current location - 64MB. position is %s\n",fpos)
            for i = 1,64 do
                for j = 1,256 do
                    n = sys.read(bios, bbuff, 4096)
                    if n < 0 then
                        sys.print("file read failed because '%s'\n",sys.errstr())
                        return
                    end
                end
            end
            ftime = sys.millisec()
            etime = (ftime - stime) / 1000.0
            rate = 64 / etime
            sys.print("64MB file read completed in %fs\n",etime)
            sys.print("io (read) speed is %f MB/s\n", rate)

            sys.print("\n\n -- re-reading file from secondary decriptor --\n");
            -- read and seek tests
            -- here we seek back to start using a lua number and read the whole file
            stime = sys.millisec()
            for i = 1,256 do
                for j = 1,256 do
                    n = sys.read(bios, bbuff, 4096)
                    if n < 0 then
                        sys.print("file re-read failed because '%s'\n",sys.errstr())
                        return
                    end
                end
            end
            ftime = sys.millisec()
            etime = (ftime - stime) / 1000.0
            rate = 256 / etime
            sys.print("256MB file read completed in %fs\n",etime)
            sys.print("io (read) speed is %f MB/s\n", rate)
            
            sys.print("setting error string\n")
            sys.werrstr("error string check")
            sys.print("getting error string\n")
            sys.print("error string is: '%s'\n",sys.errstr())
           
           -- auxillary read/write tests --
            sys.print("\n\nauxillary read/write tests\n\n");
            
            
            -- rewind the test file --
            fpos = sys.seek(bios, 0, sys.SEEKSTART) -- fpos should be a 64 bit boxed int (cdata)
            local auxbuf = sys.mkBuffer(65536)

            -- exercise readn by reading 64k from the test file --
            local numbytes = sys.readn(bios, auxbuf, 65536)
            sys.print("number of bytes read from openbios is %d\n",numbytes)
            sys.print("new auxbuf len is %d\n", auxbuf.len)
            if numbytes ~= 65536 then
                sys.print("init: test/readn - error, bytes read %d not equal to 65536\n",numbytes)
            else
                sys.print("init: test/readn - passed\n")
            end
            
            -- exercise pwrite by writing all 0xFF to middle of file --
            -- first seek to the beginning of the file --
            fpos = sys.seek(bios, 0, sys.SEEKSTART)
            -- current location is 0
            
            -- now write all 0xFF to middle
            for i = 0, 65535 do
                auxbuf.data[i] = 0xff
            end
            auxbuf.len = 65536
            numbytes = sys.pwrite(bios, auxbuf, 0, 128*1024*1024)  -- 128 MB into file
            sys.print("wrote 64k of 0xff to middle of file\n")
            -- file position should still be 0
            local oldpos = fpos
            fpos = sys.seek(bios, 0, sys.SEEKRELA)
            if fpos ~= oldpos then
                sys.print("init: test/pwrite - error, file position has moved to %s from %s\n",fpos,oldpos)
            else
                sys.print("init: test/pwrite - good file position, wrote %d bytes\n",numbytes)
            end
            
            -- seek to the written location and read back
            fpos = sys.seek(bios, 128*1024*1024, sys.SEEKSTART)
            numbytes = sys.readn(bios, auxbuf, 65536)
            if numbytes ~= 65536 then
                sys.print("init: test/pwrite - error\n")
                sys.print("init: test/pwrite - error, wrong number of bytes re-read %d\n",numbytes)
                return
            end
            for i = 0,auxbuf.len-1 do
                if auxbuf.data[i] ~= 0xff then
                    sys.print("init: test/pwrite - error\n")
                    sys.print("init: test/pwrite - data %d not as written at byte %d\n",auxbuf.data[i],i)
                    return
                end
            end
            
            -- exercise pread --
            
            -- read and verify 64k buffer of zeros at 0 --
            fpos = sys.seek(bios, 0, sys.SEEKSTART)
            numbytes = sys.pread(bios, auxbuf, 65536, 0)
            sys.print("init: after pread seek 0 relative = %s\n",sys.seek(bios, 0, sys.SEEKRELA))
            if numbytes ~= 65536 then
                sys.print("init: test/pread - read length error\n")
                sys.print("init: test/pread - error, wrong number of bytes read %d\n",numbytes)
                return
            end
            for i = 0,auxbuf.len-1 do
                if auxbuf.data[i] ~= 0x00 then
                    sys.print("init: test/pread - verify error\n")
                    sys.print("init: test/pread - data %d not as written at byte %d\n",auxbuf.data[i], i)
                    return
                end
            end
            -- position should still be at 128M --
            sys.print("init: test/pread: verify - fpos is %s\n",fpos)
            oldfpos = fpos
            fpos = sys.seek(bios, 0, sys.SEEKRELA)
            sys.print("init: test/pread: verify new fpos 0 relative is %s\n",fpos)
            if fpos ~= oldfpos then
                sys.print("init: test/pread - position error\n")
                sys.print("init: test/pread: - file position has moved from %s to %s\n",oldfpos, fpos)
                return
            end
            
            --- CWD and REMOVE ---
            
            sys.print("\n\n -- testing CWD and remove functions --\n\n\n -- in root -- \n")
            
            --- test should fail ---
            
            local bios = nil
            obios = sys.open("openbios", sys.OREAD)
            if not obios then
                sys.print(" ** could not open openbios because: '%s'\n",sys.errstr())
            else
                sys.print(" ** opened openbios, but shouldn't have ** \n")
                obios = nil
                return
            end

            --- test should succeed ---
            
            sys.chdir("/testing/boot")
            sys.print("\n -- in /testing/boot -- \n")
            
            obios = sys.open("openbios", sys.ORDWR)
            if not obios then
                sys.print(" ** could not open openbios because: '%s'\n",sys.errstr())
                return
            else
                sys.print(" ** opened openbios ** \n")
            end

            --- stat / wstat tests ---
            
                --- stat via path and fd -- should succeed ---
            
            local rc, sdir = sys.stat("openbios")
            sys.print("\n\nstat return code was %d\n",rc)
            sys.print("*** stat information for openbios is: %s\n", sdir)
            
            rc, sdir = sys.fstat(obios)
            sys.print("\n\nfstat return code was %d\n",rc)
            sys.print("*** fstat information for openbios is: %s\n", sdir)
            
                --- wstat and fwstat tests, should succeed ---
                    -- first save the stat information  from openbios
                    local ostat = sdir
                    local nstat = sys.nulldir()
                    local cstat = nil
                    local perms = 0 
                    
                    --- fd stat tests ---
                        
                        -- change file name
                        nstat.name = "newbios"
                        assert(0 == sys.fwstat(obios, nstat), "init/test/fwstat error: unable to change filename")
                        rc, cstat = sys.fstat(obios)
                        assert("newbios" == cstat.name, "init/test/fwstat error: file name didnt change")
                        
                        -- change owner
                            -- (can't change owner in emu)
                            
                        -- change group
                        nstat.uid = ""
                        nstat.gid = "everyone"    -- should work on osx
                        assert(0 == sys.fwstat(obios, nstat), "init/test/fwstat error: unable to change group")
                        rc, cstat = sys.fstat(obios)
                        assert("everyone" == cstat.gid, "init/test/fwstat error: group didnt change")
                        
                        -- change permissions mode
                        nstat.gid = ""
                        perms = tonumber("777", 8)
                        nstat.mode = perms
                        assert(0 == sys.fwstat(obios, nstat), "init/test/fwstat error: unable to change permissions")
                        rc, cstat = sys.fstat(obios)
                        assert(perms == cstat.mode, "init/test/fwstat error: permissions didnt change")
                        
                        -- change mod time
                        nstat.mode = -1
                        nstat.mtime = 12345678
                        sys.print("init/test/fwstat: mod time before attempting change = %d\n",cstat.mtime)
                        assert(0 == sys.fwstat(obios, nstat), "init/test/fwstat error: unable to change last mod time")
                        rc, cstat = sys.fstat(obios)
                        sys.print("init/test/fwstat: mod time after attempting change = %d\n",cstat.mtime)
                        assert(12345678 == cstat.mtime, "init/test/fwstat error: mod time didnt change")
                        
                        -- change access time
                        nstat.mtime = -1
                        nstat.atime = 12345678
                        assert(0 == sys.fwstat(obios, nstat), "init/test/fwstat error: unable to change last access time")
                        rc, cstat = sys.fstat(obios)
                        assert(12345678 == cstat.atime, "init/test/fwstat error: access time didnt change")
                       
                        -- change file length to 1/2
                        nstat.atime = -1
                        nstat.length = 128*1024*1024
                        assert(0 == sys.fwstat(obios, nstat), "init/test/fwstat error: unable to change file length to 128MB")
                        rc, cstat = sys.fstat(obios)
                        assert(128*1024*1024 == cstat.length, "init/test/fwstat error: file length didnt change")
                       
                     --- path stat tests ---
                     
                        -- restore saved stat info for obios
                        assert(0 == sys.fwstat(obios, ostat), "init/test/wstat error: couldnt restore file state for wstat")
                        rc, cstat = sys.fstat(obios)
                
                        -- change file name
                        nstat.atime = -1
                        nstat.name = "newbios"
                        sys.print("init/test/wstat: filename before attempting change = %s\n",cstat.name)
                        assert(0 == sys.wstat("openbios", nstat), "init/test/wstat error: unable to change filename")
                        obios = sys.open("newbios", sys.ORDWR)
                        if not obios then
                            sys.print("init/test/wstat: wasn't able to reopen file under new name\n")
                            return
                        end
                        
                        rc, cstat = sys.fstat(obios)
                        sys.print("init/test/wstat: filename after attempting change = %s\n",cstat.name)
                        assert("newbios" == cstat.name, "init/test/wstat error: file name didnt change")
                        
                        -- change owner
                                -- cant change owner in emu
                                
                        -- change group
                        nstat.uid = ""
                        nstat.gid = "everyone"
                        assert(0 == sys.wstat("newbios", nstat), "init/test/wstat error: unable to change group")
                        rc, cstat = sys.fstat(obios)
                        assert("everyone" == cstat.gid, "init/test/wstat error: group didnt change")
                        
                        -- change permissions mode
                        nstat.gid = ""
                        perms = tonumber("777", 8)
                        nstat.mode = perms
                        assert(0 == sys.wstat("newbios", nstat), "init/test/wstat error: unable to change permissions")
                        rc, cstat = sys.fstat(obios)
                        assert(perms == cstat.mode, "init/test/wstat error: permissions didnt change")
                        
                        -- change mod time
                            -- this doesn't make sense with wstat because opening the file path itself updates the mod time
                            
                        -- change access time
                        nstat.mode = -1
                        nstat.mtime = -1
                        nstat.atime = 12345678
                        assert(0 == sys.wstat("newbios", nstat), "init/test/wstat error: unable to change last access time")
                        rc, cstat = sys.fstat(obios)
                        assert(12345678 == cstat.atime, "init/test/wstat error: access time didnt change")
                    
                        -- change file length to 1/4
                        nstat.atime = -1
                        nstat.length = 64*1024*1024
                        sys.print("init/test/wstat: file length before attempting change = %s\n",cstat.length)
                        assert(0 == sys.wstat("newbios", nstat), "init/test/wstat error: unable to change file length to 64MB")
                        rc, cstat = sys.fstat(obios)
                        sys.print("init/test/wstat: file length after attempting change = %s\n",cstat.length)
                        assert(64*1024*1024 == cstat.length, "init/test/wstat error: file length didnt change")
                       

                                                
             --- end of stat tests ---           
                       
                       
            -- back into CWD tests
            
            sys.chdir("/")
            sys.print("\n -- in root -- \n")
            
            --- should fail again --
            obios = sys.open("newbios", sys.OREAD)
            if not obios then
                sys.print(" ** could not open openbios because: '%s'\n",sys.errstr())
            else
                sys.print(" ** opened openbios, but shouldn't have ** \n")
                return
            end

            sys.print("the path associated with descriptor 'bootdir' is '%s'\n",sys.fd2path(bootdir));
            
            sys.print("removing openbios file\n")
            local er = sys.remove("/testing/boot/newbios")
            sys.print("return value is %d, err msg is: %s\n",er,sys.errstr())
            
            sys.print("removing boot directory\n")
            local er = sys.remove("/testing/boot")
            sys.print("return value is %d, err msg is: %s\n",er,sys.errstr())

            sys.print("trying to remove non existent 'xyzzy'\n")
            local er = sys.remove("/testing/xyzzy")
            sys.print("return value is %d, err msg is: %s\n",er,sys.errstr())

        end
    end
end
    
-- init task --
function _init_(self)
    -- stupid simple init starts some child procs and exits after a few minutes
    local sys = self.sys
    self.init()
 
    local myconsole = sys.open("#c/cons", sys.OWRITE)
    sys.fprint(myconsole,"(%s): starting up, the time on the console is %s\n",self.name, os.date())

    sys.print("\n\n\ninit: spawning dirtracker children\n")
    
    local taskA = sys.spawn(dirtracker, "taskA","/",314)
    local taskB = sys.spawn(dirtracker, "taskB","/fd",271)
    local taskC = sys.spawn(dirtracker, "taskC","/env",141)
    
    -- give the dirtracker demo time to run
    for i=1,10 do
        sys.sleep(500)
        sys.print("\ninit: ****************************** TICK: %d ****************************\n",i);
    end
    
    -- run file system tests
    testfs(sys)
    
end

-- the demo 'dirtracker' task --
function dirtracker(self, path, sleeptime)
    --- task initialization ---
    local sys = self.sys
    self.init()
    
    -- main body
    for i=1,10 do
        local root = sys.open(path, sys.OREAD)
        if (root.fd < 0) then
            sys.print("(%s) could not open path '%s'\n",self.name,path)
        else
            --sys.print("(%s) root is %s\n",self.name,root)
        end
            
        -- display its directory contents
        do
            local need_hdr = true
            while true do
                local dirpack = sys.dirread(root)
                if dirpack.num == 0 then break end
                if need_hdr then
                    sys.print("\n(%s): %s\n",self.name,path)
                    sys.print("(%s): perms            uid          gid          size               atime           name\n",self.name)
                    need_hdr = false
                end
                
                local dir = dirpack.dirs
                for i=0, dirpack.num-1 do
                    sys.print("(%s): %s\n",self.name,dir)
                    dir = dir + 1
                end
             end
             --io.flush()
             sys.sleep(sleeptime)
        end
    end

end

------------ node9 startup --------------
-- bind to the kernel and root process (init)
init_pid = 1
rootvp = node9.procpid(init_pid)
init = proc.new(_init_, rootvp, init_pid)
init.name = "init"
schd.ready(init)

-- when scheduler exits, we exit
io.write(os.date(),"  node9/sched:  starting 'init'\n") io.flush()
schd.start()
