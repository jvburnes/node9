-- system interface objects --
-- (see kernel startup for available kernel interfaces)
local S = {}
local stat = {}

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
    
--[[
            
            Support Functions

]]--

-- unbundles a kernel dir into a node9 sys_dir (dirstat entity)
-- (stat pack/unpack)
local function s_unpack(sdir, kdir)
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

-- misc utility functions
function S.mkcstr(s)
    return ffi.new("char [?]", #s+1, s)
end

local mkcstr = S.mkcstr

local function date(otime)
    return os.date("%c",otime)
end

--[[
            
            System Calls

]]-- 
-- i/o buffer functions
function S.mkBuffer(size)
    local buf = ffi.gc(n9.mkBuffer(size), n9.freeBuffer)
    return buf
end

local mkBuffer = S.mkBuffer

--
-- sys requests
--   
function S.open(vp, s_open, path, mode)
    --local s_open = srq.open
    s_open.s = mkcstr(path)
    s_open.mode = mode
    n9.sysreq(vp, n9.Sys_open)
    coroutine.yield()
    local fd = s_open.ret
    if fd ~= nil then
        return ffi.gc(fd, n9.free_fd)
    else
        return nil
    end
end

function S.create(vp, s_create, path, mode, perm)
    s_create.s = mkcstr(path)
    s_create.mode = mode 
    s_create.perm = perm
    n9.sysreq(vp, n9.Sys_create)
    coroutine.yield()
    local fd = s_create.ret
    if fd ~= nil then
        return ffi.gc(fd, n9.free_fd)
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
function S.dup(vp, sdup, oldfd, newfd)
    s_dup.old = oldfd
    s_dup.new = newfd
    n9.sysreq(vp, n9.Sys_dup)
    coroutine.yield()
    return s_dup.ret
end
  
-- sys.fildes creates a new file descriptor object by duplicating the 
-- file descriptor with handle 'fd'.  it returns the descriptor object
-- or nil if creation failed
function S.fildes(vp, s_fildes, fdnum)
    s_fildes.fd = fdnum
    n9.sysreq(vp, n9.Sys_fildes)
    coroutine.yield()
    local fd = s_fildes.ret
    if fd ~= nil then
        return ffi.gc(fd, n9.free_fd)
    else
        return nil
    end
end    

-- sys.seek: seek to the specified location in fd
--      fd: an open file descriptor object
--      offset: can be a lua number or signed 64 bit cdata
--      start: specifies where to seek from and is one of:
--          sys.SEEKSTART (from beginning of file)
--          sys.SEEKRELA  (from current location)
--          sys.SEEKEND   (relative to end of file, usually negative)

function S.seek(vp, s_seek, fd, offset, start)
    s_seek.fd = fd
    s_seek.off = offset
    s_seek.start = start
    n9.sysreq(vp, n9.Sys_seek)
    coroutine.yield()
    return s_seek.ret
end

-- returns the largest I/O possible on descriptor fd's channel
-- without splitting into multiple operations, 0 means undefined
function S.iounit(vp, s_iounit, fd)
    s_iounit.fd = fd
    n9.sysreq(vp, n9.Sys_iounit)
    coroutine.yield()
    return s_iounit.ret
end

-- accepts fd, preallocated cdef array of unsigned byte
-- and fills buffer with read data
-- returns number of bytes read
function S.read(vp, s_read, fd, buf, nbytes)
    s_read.fd = fd
    s_read.buf = buf
    s_read.nbytes = nbytes
    n9.sysreq(vp, n9.Sys_read)
    coroutine.yield()
    return s_read.ret
end

function S.readn(vp, s_readn, fd, buf, nbytes)
    s_readn.fd = fd
    s_readn.buf = buf
    s_readn.n = nbytes
    n9.sysreq(vp, n9.Sys_readn)
    coroutine.yield()
    return s_readn.ret
end

function S.pread(vp, s_pread, fd, buf, nbytes, offset)
    s_pread.fd = fd
    s_pread.buf = buf
    s_pread.n = nbytes
    s_pread.off = offset
    n9.sysreq(vp, n9.Sys_pread)
    coroutine.yield()
    return s_pread.ret
end

-- write buf to file descriptor fd
-- entire buffer will be written, unless overridden
-- by optional length argument
function S.write(vp, s_write, fd, buf, ...)
    local args = {...} -- optional number of bytes to write
    s_write.fd = fd
    s_write.buf = buf
    s_write.nbytes = args[1] or buf.len
    n9.sysreq(vp, n9.Sys_write)
    coroutine.yield()
    return s_write.ret
end

function S.pwrite(vp, s_pwrite, fd, buf, nbytes, offset)
    s_pwrite.fd = fd
    s_pwrite.buf = buf
    if nbytes == 0 then
        s_pwrite.n = buf.len
    else
        s_pwrite.n = nbytes
    end
    s_pwrite.off = offset
    n9.sysreq(vp, n9.Sys_pwrite)
    coroutine.yield()
    return s_pwrite.ret
end
  
function S.sprint(fmt, ...)
    return string.format(fmt, ...)
end

function S.print(vp, s_print, fmt, ...)
    local tstr = string.format(fmt, ...)
    local tbuf = mkcstr(tstr)
    s_print.buf = tbuf
    s_print.len = #tstr
    n9.sysreq(vp, n9.Sys_print)
    coroutine.yield()
    return s_print.ret
end

function S.fprint(vp, s_fprint, fd, fmt, ...)
    local tstr = string.format(fmt, ...)
    local tbuf = mkcstr(tstr)
    s_fprint.fd = fd
    s_fprint.buf = tbuf
    s_fprint.len = #tstr
    n9.sysreq(vp, n9.Sys_fprint)
    coroutine.yield()
    return s_fprint.ret
end

--[[
    
function S.stream(vp, srq, src, dst, bufsize)
    n9.sys_stream(vp, src, dst, bufsize)
    local ret = coroutine.yield()
    return ret[0]
end
]]--

-- construct a stat template
function S.nulldir()
    return stat.new(-1)
end

-- returns the stat results for file path
-- returns a table {int rc, Sys_dir} 
-- where: rc = 0 on success, -1 on failure
-- Sys_Dir is created and populated with appropriate values
-- on failure Sys_Dir is nil
function S.stat(vp, s_stat, path)
    s_stat.s = mkcstr(path)
    n9.sysreq(vp, n9.Sys_stat)
    coroutine.yield()
    local rc = -1
    local newstat = nil
    local kdir = s_stat.ret
    if kdir ~= nil then
        rc = 0
        newstat = stat.new()
        s_unpack(newstat, kdir)
    end
    n9.free_dir(kdir)
    return rc, newstat
end

function S.fstat(vp, s_fstat, fd)
    s_fstat.fd = fd
    n9.sysreq(vp, n9.Sys_fstat)
    coroutine.yield()
    local rc = -1
    local newstat = nil
    local kdir = s_fstat.ret
    if kdir ~= nil then
        rc = 0
        newstat = stat.new()
        s_unpack(newstat, kdir)
    end
    n9.free_dir(kdir)
    return rc, newstat
end

function S.wstat(vp, s_wstat, path, sdir)
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
    n9.sysreq(vp, n9.Sys_wstat)
    coroutine.yield()
    return s_wstat.ret
end

function S.fwstat(vp, s_fwstat, fd, sdir)
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
    n9.sysreq(vp, n9.Sys_fwstat)
    coroutine.yield()
    return s_fwstat.ret
end

function S.dirread(vp, s_dirread, fd)
    s_dirread.fd = fd
    n9.sysreq(vp, n9.Sys_dirread)
    coroutine.yield()
    return ffi.gc(s_dirread.ret, n9.free_dirpack)
end
  
function S.errstr()
    local estr = n9.sys_errstr(vp)
    if estr ~= nil then 
        return ffi.string(estr)
    else
        return nil
    end
end
    
function S.werrstr(vp, errstr)
    local err = mkcstr(errstr)
    n9.sys_werrstr(vp, err)
    return 0
end

--[[
function S.bind(vp, srq, name, old, flags)
    n9.sys_bind(vp, name, old, flags)
    local ret = coroutine.yield()
    return ret[0]
end

function S.mount(vp, srq, FD, AFD, oldstring, flags, anamestring)
    n9.sys_mount(vp, FD, AFD, oldstring, flags, anamestring)
    local ret = coroutine.yield()
    return ret[0]
end

function S.unmount(vp, srq, namestring, oldstring)
    n9.sys_unmount(vp, namestring, oldstring)
    local ret = coroutine.yield()
    return ret[0]
end
]]--    

function S.remove(vp, s_remove, path)
    local pth = mkcstr(path)
    s_remove.s = pth
    n9.sysreq(vp, n9.Sys_remove)
    coroutine.yield()
    return s_remove.ret
end

function S.chdir(vp, s_chdir, path)
    local pth = mkcstr(path)
    s_chdir.path = pth
    n9.sysreq(vp, n9.Sys_chdir)
    coroutine.yield()
    return s_chdir.ret
end

function S.fd2path(vp, s_fd2path, fd)
    s_fd2path.fd = fd
    n9.sysreq(vp, n9.Sys_fd2path)
    coroutine.yield()
    if s_fd2path.ret == nil then
        return ""
    end
    local pstring = ffi.string(s_fd2path.ret)
    -- kernel alloc'd, so let it go
    n9.free_cstring(s_fd2path.ret)
    return pstring
end

--[[
function S.pipe(vp, srq)
    n9.sys_pipe(pid)
    local ret = coroutine.yield()
    return ret
end

function S.dial(vp, srq, addrstring, localstring)
    n9.sys_dial(vp, addrstring, localstring)
    local ret = coroutine.yield()
    return ret
end

function S.announce(vp, srq, addrstring)
    n9.sys_announce(vp, addrstring)
    local ret = coroutine.yield()
    return ret
end

function S.listen(vp, srq, connection)
    n9.sys_listen(vp, connection)
    local ret = coroutine.yield()
    return ret
end

function S.file2chan(vp, srq, dirstring, filestring)
    n9.sys_chdir(vp, dirstring, filestring)
    local ret = coroutine.yield()
    return ret[0]
end

function S.export(vp, srq, FD, dirstring, flags)
    n9.sys_export(vp, FD, dirstring, flags)
    local ret = coroutine.yield()
    return ret[0]
end
--]]    
function S.millisec()
    return n9.sys_millisec()
end

function S.sleep(vp, s_sleep, millisecs)
    n9.sys_sleep(vp, millisecs)   -- non-standard async req
    coroutine.yield()
    return s_sleep.ret
end
--[[    
function S.fversion(vp, srq, FD, bufsize, versionstring)
    n9.sys_fversion(vp, FD, bufsize, versionstring)
    local ret = coroutine.yield()
    return ret
end

function S.fauth(vp, srq, FD, anamestring)
    n9.sys_fauth(vp, FD, anamestring)
    local ret = coroutine.yield()
    return ret[0]
end

function S.pctl(vp, srq, flags, movefd_list)
    n9.sys_pctl(vp, flags, movefd_list)
    local ret = coroutine.yield()
    return ret[0]
end
]]--

-- create a new task, this is a little convoluted
-- new_proc and make_ready are inherited from the kernel / scheduler
function S.spawn(vp, p, s_spawn, fun, name, ...)
    local args = {...}
    -- create the kernel vproc
    n9.sysreq(vp, n9.Sys_spawn)
    coroutine.yield()
    local child_pid = s_spawn.ret 
    local child_vproc = n9.procpid(child_pid)    -- sync call
    -- specify the kernel finalizer for child_vproc
    -- free_vproc runs async, notifies proc group and doesn't block
    ffi.gc(child_vproc, n9.vproc_exit)
    -- create the lua task, run its initializer and make it ready
    -- (new_proc and make_ready are on loan from the kernel)
    local nproc = new_proc(fun, child_vproc)
    nproc.app = p.app
    nproc.name = name or p.name
    nproc.args = args               -- startup value is arglist
    
    -- bind the new proc to the shared app global space
    setmetatable(nproc, {__index = nproc.app.env, __newindex = nproc.app.env})
    -- redirect the start function global refs to coroutine global refs
    setfenv(fun, init_proxy)

    make_ready(nproc)
end

-- system constants

S.const = const

return S
