 --[[ff
                NATIVE LUA KERNEL MODULE
                  (pure lua component)
]]--

local M = {}        -- lua module instance

 --[[
        
          Foreign Function and C Kenel Interface
        
]]--

local ffi = require 'ffi'
local bit = require 'bit'
band = bit.band
bor = bit.bor
brshift = bit.rshift
local List = require 'pl.List'

-- load the kernel headers, cdefs and prototypes

-- (cheesy impedance match for FFI)
ffi.cdef[[
typedef void uv_work_t;
]]

local function load_cdef(hdr)
    local header = io.open(_noderoot .. hdr, "rb")
    assert(header, string.format("node9/load_cdef: could not load C header '%s'\n",hdr))
    local cdefs = header:read("*all")
    header:close()
    ffi.cdef(cdefs)
end

load_cdef("/module/ninevals.h")
load_cdef("/module/kern.h")
load_cdef("/module/node9.h")
load_cdef("/module/syscalls.h")

 -- load the system constants, kinda ugly
local sysconst = {}

local sc = io.open(_noderoot .. "/module/sysconst.h", "rb")
assert(sc, "node9/libnode9: could not load system constants")

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

--[[
            
            Utility Objects and Support Functions

]]--

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

local function date(otime)
    return os.date("%c",otime)
end

local stat = {}

function stat.new(...)
    local args = {...}
    local self = {}
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
        {
--[[            __tostring = 
            function(dstat) 
                return string.format("<dirstat>: name: %s, len: %s, uid: %s, gid: %s, mtime: %s", 
                    dstat.name, dstat.length, dstat.uid, dstat.gid, date(dstat.mtime))
            end
]]--
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
    )
                    
    return self
end
    
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
local function mkcstr(s)
    return ffi.new("char [?]", #s+1, s)
end

-- initialize the CDEF metamethods --

-- mode string generator --

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

-- now that we have the interface defined, bind to the library
local n9 = ffi.load('node9')

M.n9 = n9

--[[

        Process Mgmt / App Loaders and Environments
            
]]--

M.sched = require 'schedulers.roundrobin'
local env = require 'environments'
local sched = M.sched
local procs = {}

-- (do we want to do the cacheing or leave that to lua/os?)
local loaded = {}
local mpaths = {"/appl","/lib", "/module"}

-- shared global app environments
local init_proxy = {}
local init_proxy_mt = {}

function init_proxy_mt:__index(k)
    return getfenv(0)[k]
end

function init_proxy_mt:__newindex(k,v)
    getfenv(0)[k] = v
end
setmetatable(init_proxy, init_proxy_mt)

-- support functions

-- just returns the associated vproc
function M.procpid(pid)
    return n9.procpid(pid)
end

-- cache and share a module read-only
function share(modname, mod, cache)
    cache[modname] = mod
    -- we're a shared module so make us readonly
    local new_mt = getmetatable(mod) or {}
    new_mt.__newindex = 
        function(k,v)
            error("attempt to modify shared module '" .. modname .. "'", 2)
        end
    
    setmetatable(mod, new_mt)
    
    return mod
end


--[[
            
            Sys Calls

]]-- 


-- finally generate the shared system library interface
-- 
-- sys has visibility into kernel, but only exposes functions via this interface
-- each process contains a cached set of union offsets into its call record
sys = {}

function sys.new()
    local self = {}
    -- inherit the system constants and make the shared lib read-only
    setmetatable(self, { __index = sysconst })
    
    --
    -- sys requests
    --   
    function self.open(path, mode)
        local c_proc = sched.curproc
        c_proc.s_open.s = mkcstr(path)
        c_proc.s_open.mode = mode
        n9.sysreq(c_proc.vproc, n9.Sys_open)
        coroutine.yield()
        local fd = c_proc.s_open.ret
        if fd ~= nil then
            return ffi.gc(fd, n9.free_fd)
        else
            return nil
        end
    end

    function self.create(path, mode, perm)
        local c_proc = sched.curproc
        c_proc.s_create.s = mkcstr(path)
        c_proc.s_create.mode = mode 
        c_proc.s_create.perm = perm
        n9.sysreq(c_proc.vproc, n9.Sys_create)
        coroutine.yield()
        local fd = c_proc.s_create.ret
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
    function self.dup(oldfd, newfd)
        local c_proc = sched.curproc
        c_proc.s_dup.old = oldfd
        c_proc.s_dup.new = newfd
        n9.sysreq(c_proc.vproc, n9.Sys_dup)
        coroutine.yield()
        return c_proc.s_dup.ret
    end
      
    -- sys.fildes creates a new file descriptor object by duplicating the 
    -- file descriptor with numeric handle 'fd'.  it returns the descriptor object
    -- or nil if creation failed
    function self.fildes(fdnum)
        local c_proc = sched.curproc
        c_proc.s_fildes.fd = fdnum
        n9.sysreq(c_proc.vproc, n9.Sys_fildes)
        coroutine.yield()
        local fd = c_proc.s_fildes.ret
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

    function self.seek(fd, offset, start)
        local c_proc = sched.curproc
        c_proc.s_seek.fd = fd
        c_proc.s_seek.off = offset
        c_proc.s_seek.start = start
        n9.sysreq(c_proc.vproc, n9.Sys_seek)
        coroutine.yield()
        return c_proc.s_seek.ret
    end

    -- returns the largest I/O possible on descriptor fd's i/o channel
    -- without splitting into multiple operations, 0 means undefined
    function self.iounit(fd)
        local c_proc = sched.curproc
        c_proc.s_iounit.fd = fd
        n9.sysreq(c_proc.vproc, n9.Sys_iounit)
        coroutine.yield()
        return c_proc.s_iounit.ret
    end

    -- accepts fd, preallocated cdef array of unsigned byte
    -- and fills buffer with read data
    -- returns number of bytes read
    function self.read(fd, readbuf, nbytes)
        local c_proc = sched.curproc
        c_proc.s_read.fd = fd
        c_proc.s_read.buf = readbuf.buf
        c_proc.s_read.nbytes = nbytes
        n9.sysreq(c_proc.vproc, n9.Sys_read)
        coroutine.yield()
        return c_proc.s_read.ret
    end

    function self.readn(fd, readbuf, nbytes)
        local c_proc = sched.curproc
        c_proc.s_readn.fd = fd
        c_proc.s_readn.buf = readbuf.buf
        c_proc.s_readn.n = nbytes
        n9.sysreq(c_proc.vproc, n9.Sys_readn)
        coroutine.yield()
        return c_proc.s_readn.ret
    end

    function self.pread(fd, readbuf, nbytes, offset)
        local c_proc = sched.curproc
        c_proc.s_pread.fd = fd
        c_proc.s_pread.buf = readbuf.buf
        c_proc.s_pread.n = nbytes
        c_proc.s_pread.off = offset
        n9.sysreq(c_proc.vproc, n9.Sys_pread)
        coroutine.yield()
        return c_proc.s_pread.ret
    end

    -- write buf to file descriptor fd
    -- entire buffer will be written, unless overridden
    -- by optional length argument
    function self.write(fd, writebuf, ...)
        local c_proc = sched.curproc
        local args = {...} -- optional number of bytes to write
        c_proc.s_write.fd = fd
        c_proc.s_write.buf = writebuf.buf
        c_proc.s_write.nbytes = args[1] or writebuf.len
        n9.sysreq(c_proc.vproc, n9.Sys_write)
        coroutine.yield()
        return c_proc.s_write.ret
    end

    function self.pwrite(fd, writebuf, nbytes, offset)
        local c_proc = sched.curproc
        c_proc.s_pwrite.fd = fd
        c_proc.s_pwrite.buf = writebuf.buf
        if nbytes == 0 then
            c_proc.s_pwrite.n = writebuf.len
        else
            c_proc.s_pwrite.n = nbytes
        end
        c_proc.s_pwrite.off = offset
        n9.sysreq(c_proc.vproc, n9.Sys_pwrite)
        coroutine.yield()
        return c_proc.s_pwrite.ret
    end
      
    function self.sprint(fmt, ...)
        return string.format(fmt, ...)
    end

    function self.print(fmt, ...)
        local c_proc = sched.curproc
        local tstr = string.format(fmt, ...)
        local tbuf = mkcstr(tstr)
        c_proc.s_print.buf = tbuf
        c_proc.s_print.len = #tstr
        n9.sysreq(c_proc.vproc, n9.Sys_print)
        coroutine.yield()
        return c_proc.s_print.ret
    end

    function self.fprint(fd, fmt, ...)
        local c_proc = sched.curproc
        local tstr = string.format(fmt, ...)
        local tbuf = mkcstr(tstr)
        c_proc.s_fprint.fd = fd
        c_proc.s_fprint.buf = tbuf
        c_proc.s_fprint.len = #tstr
        n9.sysreq(c_proc.vproc, n9.Sys_fprint)
        coroutine.yield()
        return c_proc.s_fprint.ret
    end

    --[[
        
    function self.stream(vp, srq, src, dst, bufsize)
        n9.sys_stream(vp, src, dst, bufsize)
        local ret = coroutine.yield()
        return ret[0]
    end
    ]]--

    -- construct a stat template
    function self.nulldir()
        return stat.new(-1)
    end

    -- returns the stat results for file path
    -- returns a tuple int rc, Sys_dir 
    -- where: rc = 0 on success, -1 on failure
    -- Sys_Dir is created and populated with appropriate values
    -- on failure Sys_Dir is nil
    function self.stat(path)
        local c_proc = sched.curproc
        c_proc.s_stat.s = mkcstr(path)
        n9.sysreq(c_proc.vproc, n9.Sys_stat)
        coroutine.yield()
        local rc = -1
        local newstat = nil
        local kdir = c_proc.s_stat.ret
        if kdir ~= nil then
            rc = 0
            newstat = stat.new()
            s_unpack(newstat, kdir)
        end
        n9.free_dir(kdir)
        return rc, newstat
    end

    function self.fstat(fd)
        local c_proc = sched.curproc
        c_proc.s_fstat.fd = fd
        n9.sysreq(c_proc.vproc, n9.Sys_fstat)
        coroutine.yield()
        local rc = -1
        local newstat = nil
        local kdir = c_proc.s_fstat.ret
        if kdir ~= nil then
            rc = 0
            newstat = stat.new()
            s_unpack(newstat, kdir)
        end
        n9.free_dir(kdir)
        return rc, newstat
    end

    function self.wstat(path, sdir)
        local c_proc = sched.curproc
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
        c_proc.s_wstat.s   = s_path
        c_proc.s_wstat.dir = s_kdir
        n9.sysreq(c_proc.vproc, n9.Sys_wstat)
        coroutine.yield()
        return c_proc.s_wstat.ret
    end

    function self.fwstat(fd, sdir)
        local c_proc = sched.curproc
        -- (create local refs to prevent collection during yield)
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
        c_proc.s_fwstat.fd  = fd
        c_proc.s_fwstat.dir = s_kdir
        n9.sysreq(c_proc.vproc, n9.Sys_fwstat)
        coroutine.yield()
        return c_proc.s_fwstat.ret
    end

    function self.dirread(fd)
        local c_proc = sched.curproc
        c_proc.s_dirread.fd = fd
        n9.sysreq(c_proc.vproc, n9.Sys_dirread)
        coroutine.yield()
        return ffi.gc(c_proc.s_dirread.ret, n9.free_dirpack)
    end
      
    function self.errstr()
        local c_proc = sched.curproc
        local estr = n9.sys_errstr(c_proc.vproc)
        if estr ~= nil then 
            return ffi.string(estr)
        else
            return nil
        end
    end
        
    function self.werrstr(errstr)
        local c_proc = sched.curproc
        local err = mkcstr(errstr)
        n9.sys_werrstr(c_proc.vproc, err)
        return 0
    end

    -- binds name onto path indicated by 'old' according to flags
    -- returns bind # > 0 or -1 if failed
    function self.bind(name, old, flags)
        local b_name = mkcstr(name)
        local o_name = mkcstr(old)
        local c_proc = sched.curproc
        c_proc.s_bind.name = b_name
        c_proc.s_bind.on = o_name
        c_proc.s_bind.flags = flags
        n9.sysreq(c_proc.vproc, n9.Sys_bind)
        coroutine.yield()
        return c_proc.s_bind.ret
    end

    -- mounts connection on descriptor 'fd' onto 'old' according to 'flags'
    -- 'afd' is an opional authentication descriptor or nil if not required
    -- 'aname' is the subtree to mount if any or 'nil' to indicate default
    function self.mount(fd, afd, old, flags, aname)
        local m_old = mkcstr(old)
        local m_aname = nil
        if aname then m_aname = mkcstr(aname) end
        local c_proc = sched.curproc
        c_proc.s_mount.fd = fd
        c_proc.s_mount.afd = afd
        c_proc.s_mount.on = m_old
        c_proc.s_mount.flags = flags
        c_proc.s_mount.spec = m_aname
        n9.sysreq(c_proc.vproc, n9.Sys_mount)
        coroutine.yield()
        return c_proc.s_mount.ret
    end

    -- unmounts 'name' from 'old'
    -- if 'name' is nil, unmounts all current bindings to old
    function self.unmount(name, old)
        local u_name = nil
        if name then u_name = mkcstr(name) end
        local u_old = mkcstr(old)
        local c_proc = sched.curproc
        c_proc.s_unmount.name = u_name
        c_proc.s_unmount.from = u_old
        n9.sysreq(c_proc.vproc, n9.Sys_unmount)
        coroutine.yield()
        -- since previous file descriptors, no longer in use, but also not yet GC'd may hold
        -- references to the mount's data connection, we force a garbage collect which triggers
        -- the release of those references (wish there were a cleaner way to do this)
        collectgarbage()
        return c_proc.s_unmount.ret
    end

    function self.remove(path)
        local c_proc = sched.curproc
        local pth = mkcstr(path)
        c_proc.s_remove.s = pth
        n9.sysreq(c_proc.vproc, n9.Sys_remove)
        coroutine.yield()
        return c_proc.s_remove.ret
    end

    function self.chdir(path)
        local c_proc = sched.curproc
        local pth = mkcstr(path)
        c_proc.s_chdir.path = pth
        n9.sysreq(c_proc.vproc, n9.Sys_chdir)
        coroutine.yield()
        return c_proc.s_chdir.ret
    end

    function self.fd2path(fd)
        local c_proc = sched.curproc
        c_proc.s_fd2path.fd = fd
        n9.sysreq(c_proc.vproc, n9.Sys_fd2path)
        coroutine.yield()
        if c_proc.s_fd2path.ret == nil then
            return ""
        end
        local pstring = ffi.string(c_proc.s_fd2path.ret)
        -- kernel alloc'd, so let it go
        n9.free_cstring(c_proc.s_fd2path.ret)
        return pstring
    end

    --[[
    function self.pipe()
        local c_proc = sched.curproc
        n9.sys_pipe(proc.pid)
        local ret = coroutine.yield()
        return ret
    end
]]--
    -- returns tuple: (-1, nil) if failed with syserr set, or (0, Sys_Connection) if success.  
    -- since Sys_Connection is tracked by ffi garbage collection, it's the responsibility of
    -- the caller to keep at least one reference to it alive.  otherwise the memory allocated to
    -- the Sys_Connection and it's contained file descriptors and path will be deallocated out from
    -- under the user when the last ref goes out of scope
    function self.dial(addrstring, ...)
        local args = {...}
        local daddr = mkcstr(addrstring)   -- hold the refs for the duration
        local localstring = args[1] or ""
        local dlocal = mkcstr(localstring)
        local c_proc = sched.curproc
        c_proc.s_dial.d_addr = daddr
        c_proc.s_dial.d_local = dlocal
        n9.sysreq(c_proc.vproc, n9.Sys_dial)
        coroutine.yield()
        if c_proc.s_dial.ret == nil then
            return -1, nil
        else
            local conn = c_proc.s_dial.ret 
            ffi.gc(conn, n9.free_sysconn)
            return 0, conn
        end
    end

    -- announces net!protocol!service to connection server
    -- returns a connection circuit to listen on for incoming clients
    function self.announce(addrstring)
        local daddr = mkcstr(addrstring)   -- hold the ref for the duration
        local c_proc = sched.curproc
        c_proc.s_announce.d_addr = daddr
        n9.sysreq(c_proc.vproc, n9.Sys_announce)
        coroutine.yield()
        if c_proc.s_announce.ret == nil then
            return -1, nil
        else
            local conn = c_proc.s_announce.ret 
            ffi.gc(conn, n9.free_sysconn)
            return 0, conn
        end
    end

    -- waits for a connection on the announce circuit and returns
    -- an open connection to the control descriptor of the circuit
    -- to use.  the data descriptor is nil and the data file must
    -- be opened by the caller.
    function self.listen(connection)
        local c_proc = sched.curproc
        c_proc.s_listen.conn = connection
        n9.sysreq(c_proc.vproc, n9.Sys_listen)
        coroutine.yield()
        if c_proc.s_listen.ret == nil then
            return -1, nil
        else
            local conn = c_proc.s_listen.ret 
            ffi.gc(conn, n9.free_sysconn)
            return 0, conn
        end
    end

--[[
    function self.file2chan(dirstring, filestring)
        local c_proc = sched.curproc
        n9.sys_chdir(c_proc.vproc, dirstring, filestring)
        local ret = coroutine.yield()
        return ret[0]
    end
]]--
    function self.export(fd, dir, flag)
        local e_dir = mkcstr(dir)
        local c_proc = sched.curproc
        c_proc.s_export.fd = fd
        c_proc.s_export.dir = e_dir
        c_proc.s_export.flag = flag
        n9.sysreq(c_proc.vproc, n9.Sys_export)
        coroutine.yield()
        return c_proc.s_export.ret
    end
   
    function self.millisec()
        return n9.sys_millisec()
    end

    function self.sleep(millisecs)
        local c_proc = sched.curproc
        n9.sys_sleep(c_proc.vproc, millisecs)   -- non-standard async req
        coroutine.yield()
        return c_proc.s_sleep.ret
    end
    --[[    
    function self.fversion(FD, bufsize, versionstring)
        local c_proc = sched.curproc
        n9.sys_fversion(c_proc.vproc, FD, bufsize, versionstring)
        local ret = coroutine.yield()
        return ret
    end

    function self.fauth(FD, anamestring)
        local c_proc = sched.curproc
        n9.sys_fauth(c_proc.vproc, FD, anamestring)
        local ret = coroutine.yield()
        return ret[0]
    end
    ]]--
    
    function self.pctl(flags, ...)
        local args = {...}
        local movefd_list = args[1]
        local c_proc = sched.curproc
        local fdsize = 0
        local fds = nil
        if type(movefd_list) ==  "table" then
            fdsize = #movefd_list
            if fdsize > 0 then 
                fds = ffi.new("int[" .. fdsize .. "]", movefd_list)
            end
        end
        c_proc.s_pctl.flags = flags
        c_proc.s_pctl.numfds = fdsize
        c_proc.s_pctl.movefd = fds
        n9.sysreq(c_proc.vproc, n9.Sys_pctl)
        coroutine.yield()
        return c_proc.s_pctl.ret
    end

    -- create a new task, this is a little convoluted
    -- new_proc and make_ready are inherited from the kernel / scheduler
    function self.spawn(fun, ...)
        local c_proc = sched.curproc
        local args = {...}
        -- create the kernel vproc
        n9.sysreq(c_proc.vproc, n9.Sys_spawn)
        coroutine.yield()
        local child_pid = c_proc.s_spawn.ret 
        local child_vproc = n9.procpid(child_pid)    -- get C kernel virtual proc
        -- specify the kernel finalizer for child_vproc
        -- create the lua task and make it ready
        local nproc = M.proc.new(fun, child_vproc)
        -- free_vproc runs async, notifies proc group and doesn't block
        ffi.gc(child_vproc, n9.vproc_exit)
        nproc.ctxt = c_proc.ctxt        -- share the parent's context
        nproc.args = args               -- startup value is arglist
        
        -- redirect start function globals to coroutine globals
        setfenv(fun, init_proxy)

        sched.ready(nproc)
    end
    
    -- Channels are where fibers go to synchronize data exchange.
    -- If the channel has a buffer area (size>0) then send/recv
    -- will try to use data in the buffer area first.
    -- If the channel doesn't have a buffer, or the buffer's been
    -- exhausted then there can't be any further exchange unless
    -- the send operation matches a respective receive operation.
    --
    -- When a sender waits it places the value to be sent on the 
    -- pending queue, places itself on the senders queue and 
    -- yields.
    --
    -- When a receiver waits it places itself on the receivers
    -- queue and yields.  After it's rescheduled it returns the 
    -- sent value from the pending queue.
    
    
    function self.Channel(...)
        local args = {...}
        local size = args[1] or 0
        local p_pid = sched.curproc.pid
        
        local senders = List()
        local receivers = List()
        local pending = List()
        local buff = List()
        
        local self = {}

        function sendwait(v)
            local receiver = receivers:pop()
            pending:put(v)
            if receiver then
                sched.ready(receiver)
            else
                senders:put(sched.curproc)
                coroutine.yield()
            end 
        end
    
        function recvwait()
            local sender = senders:pop()
            if sender then
                sched.ready(sender)
                return pending:pop()
            end
            receivers:put(sched.curproc)
            coroutine.yield()
            return pending:pop()
        end
                
        function self.send(v)
            if size > 0 then
                if #buff < size then
                    buff:put(v)
                    return
                end
            end
            sendwait(v)
        end
        
        function self.recv()
            if size > 0 then
                if #buff > 0 then
                    return buff:pop()
                end
            end
            return recvwait()
        end

        return self 
    end
    
    -- just a simple function to allow proc to know its identity
    -- returns pid and appname as a tuple
    function self.id()
        local c_proc = sched.curproc
        return c_proc.pid, c_proc.ctxt.argv[1]
    end

    function self.env()
        local c_proc = sched.curproc
        return c_proc.ctxt.env
    end
      
    return self
end

-- precache the sys module read only
local ksys = share('sys',sys.new(), loaded)

-- PROCESS MANAGEMENT --

function M.gen_vproc(pproc)
    return n9.make_vproc(pproc)
end

M.proc = {}

-- create a new proc from the specified function and kernel vproc (with startup args)
function M.proc.new(fun, vproc)
    -- create basic structure
    -- this is exposed to the scheduler and interface importer
    -- cache the request record offsets.  Is there any easier way of doing this?
    local self = {}
    self.vproc = vproc
    local sreq = n9.sysbuf(vproc)
    self.pid =   n9.pidproc(vproc)
    -- cache the call structures
    self.s_open     = sreq.open
    self.s_create   = sreq.create
    self.s_dup      = sreq.dup
    self.s_fildes   = sreq.fildes
    self.s_seek     = sreq.seek
    self.s_iounit   = sreq.iounit
    self.s_read     = sreq.read
    self.s_readn    = sreq.readn
    self.s_pread    = sreq.pread 
    self.s_write    = sreq.write 
    self.s_pwrite   = sreq.pwrite
    self.s_print    = sreq.print
    self.s_fprint   = sreq.fprint
--     self.s_stream = sreq.stream
    self.s_stat     = sreq.stat 
    self.s_fstat    = sreq.fstat
    self.s_wstat    = sreq.wstat 
    self.s_fwstat   = sreq.fwstat
    self.s_dirread  = sreq.dirread
    self.s_bind     = sreq.bind
    self.s_mount    = sreq.mount
    self.s_unmount  = sreq.unmount
    self.s_export   = sreq.export
    self.s_remove   = sreq.remove
    self.s_chdir    = sreq.chdir
    self.s_fd2path  = sreq.fd2path
--    self.s_pipe  = sreq.pipe
    self.s_dial     = sreq.dial
    self.s_announce = sreq.announce
    self.s_listen   = sreq.listen
--    self.s_file2chan = sreq.file2chan
    self.s_sleep    = sreq.sleep
--    self.s_fversion = sreq.fversion
--    self.s_fauth = sreq.fauth
--    self.s_pctl = sreq.pctl
    self.s_spawn    = sreq.spawn
    self.s_pctl     = sreq.pctl
    
    -- create task from start function
    self.co = coroutine.create(fun)    -- create the task state
    
    -- register proc artifacts for garbage collection
    -- (needed for proper handle lifetimes)
    function self.collect()
        ffi.gc(self.vproc, n9.vproc_exit)
    end
    
    -- set proc state
    
    -- place into proc table
    procs[self.pid] = self
    return self
end

--[[
        
        Shared System Modules

]]--


-- first define a minimal buffer module
-- (right now it only creates buffer objects)
--
--[[extern void bbFree(Bytebuffer*);
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
]]--


-- this is an object wrapper around NetCDF's ByteBuffer

buffers = {}

function buffers.new()
    local M = {}
    
    -- Managed Buffer --
    -- needs "tostring", and array set/get metamethods --
    function M.new(size)
        local self = {}
        -- create buffer
        self.buf = ffi.gc(n9.bbNew(), n9.bbFree)
--        self.buf = n9.bbNew()
        n9.bbSetalloc(self.buf,size)
        -- truncate to blen bytes
        function self.setLength(blen)
            n9.bbSetlength(self.buf,blen)
        end
        
        -- fill with ch 
        function self.fill(ch)
            n9.bbFill(self.buf,ch)
        end
        
        -- put ch char at end
        function self.push(ch)
            n9.bbAppend(self.buf,ch)
        end
        
        -- appends a data buffer from lua string or byte buffer
        function self.append(data)
            if type(data) == "string" then
                -- convert to c string and append sans null
                local dstr = mkcstr(data)
                n9.bbAppendn(self.buf,dstr,#data)
            else
                -- must be a buffer, so use that part
                n9.bbCatbuf(self.buf,data.buf)
            end
        end
        
        -- inserts raw data into the buffer at location
        -- accepts a byte or string value
        function self.insert(pos,data)
            if type(data) == "number" then
                if data >= 0 and data <= 255 then
                    n9.bbInsert(self.buf,pos,data)
                else
                    error("buffer insertion: value out-of-range",2)
                end
            else
                if type(data) == "string" then
                    n9.bbInsertn(self.buf,pos,data,#data)
                else
                    error("buffer insertion: invalid type",2)
                end
            end
        end
                
        -- sets the value and len of the buffer to string data
        function self.set(data)
            if type(data) == "string" then
                local dstr = mkstr(str)
                n9.bbSetcontents(self.buf,dstr,#data)
            else
                error("buffer set: invalid type",2)
            end
        end
        
        -- reset the buffer to zero length and releases contents
        function self.null()
            n9.bbNull(self.buf)
        end
        
        -- this needs to be part of a metatable for it
        function self.tostring()
            return ffi.string(self.buf.content, self.buf.length)
        end
        
        -- returns the char * to the current contents
        function self.contents()
            return self.buf.content
        end
        
        setmetatable(self,
            {
            __tostring =
                function(buffer)
                    return ffi.string(buffer.buf.content, buffer.buf.length)
                end,
            __len =
                function(buffer)
                    return buffer.buf.length
                end,
            }
        )

        return self    
    end

    return M
end

local kbuffers = share('buffers', buffers.new(), loaded)

mod = {}

function mod.new()
 
     local self = {}

    -- reads and compiles lua mod def from current 9p namespace
    function self.read(path, ...)
       local sys = ksys
       local buffers = kbuffers
       local args = {...}
       local menv = args[1]
       local mstring = ""
       local mfunc = nil
       local stat = nil
   
       local fd = sys.open(path,sys.OREAD)
       
       if fd then
           local linebuf = buffers.new(2048)    -- many smaller files will be processed in single read
           local buf = buffers.new(8192)        -- should be sufficient default for small files
           while sys.read(fd, linebuf, 2048) ~= 0 do
               buf.append(linebuf)
           end
       
           mstring = buf.tostring()
           -- we're using luajit, so that means we have access to the
           -- more advanced 'load' method.
           mfunc, stat = load(mstring, "", "bt", menv)                      -- we get predictable module string 
        else
           stat = "no such module"
        end
        
        return mfunc,stat
    end

    ---
    --- Module Loader
    --- 
    -- load a node9 module, possibly into a restricted environment
    -- the 'mod' is the absolute pathname, less the '.lua' extension
    -- this needs to use the node9 sys.open/read instead of local file I/O 
    
    function self.mload(modname, ...)
        local args = {...}
        local renv = args[1]                -- optional restricted environment
        local status = nil
        local menv = renv or env.safe()     -- specific env or private safe one
        local newmod = nil
        local app = false
        
        -- compile a function to instantiate module
        local mfunc = nil
        if string.sub(modname,1,1) == '/' then
            -- fully qualified path in namespace
            mfunc, status = self.read(modname, menv)
        else
            -- search for it in mpaths
            local fullpath = ""
            for _,mpath in pairs(mpaths) do  
                fullpath = mpath .. "/" .. modname .. ".lua"
                mfunc, status = self.read(fullpath, menv)
                if mfunc then break end
            end
        end
        if mfunc then
            -- instantiate module by evaluating it.  this pcall executes any statements at the 
            -- module level including function definitions, static value assignment and any other
            -- immediate mode code, so be careful
            status, newmod = pcall(mfunc)
            --print("create result: status",status,"mod is",mod)
            if not status then
                status = newmod
                newmod = nil
            else
                if not newmod then
                    -- mfunc didn't return a global environment variable, so it all just loaded into 
                    -- the provided environment.  return that.
                    newmod = menv
                end
            end 
        end
        
        return newmod,status
    end
   
    -- returns a reference to a library or application module.  loads the 
    -- module if it's never been loaded before in this application context.
    --
    -- (note: unless it's a new application, each module loads into the 
    -- context of the current application.  There is a context-specific
    -- cache that prevents the app from having to reload the same module more
    -- than once -- eg: if a module loads a module that is already loaded
    -- etc)
    
    function self.import(modname,...)
        local args = {...}
        local renv = args[1]
        local menv
        local sync
        local ctxt 
        local newmod
        local status = nil
        local app = false
        
        local cproc = sched.curproc

        -- if caller asks for an empty restricted environment, they want a new
        -- new application.  after we load the module we switch to new context
        if renv then
            if type(renv) == "table" and #renv == 0 then
                -- construct application global environment for current proc
                app = true
                menv = env.safe()
                sync = args[2]      -- pick up the application sync channel
            end
        else
            menv = env.safe()
            menv.import = cproc.ctxt.env.import
        end

        -- is this a shared kernel module?
        newmod = loaded[modname]
        
        if not newmod then 
            -- has this module been loaded in this app context before?
            newmod = cproc.ctxt.loaded[modname]
            
            if not newmod then
                -- do they want to load into the default space or custom space
                newmod, status = self.mload(modname,menv) 
                if not renv then
                    if newmod then
                        share(modname, newmod, cproc.ctxt.loaded)          -- cache it in app context, read-only
                    end
                end
            end
        end
        
        -- if we're loading an app then switch to new namespace
        if app then
            -- trying to import an application module
            cproc.ctxt = {}                                 -- new app context
            cproc.ctxt.loaded = {}                          -- apps module cache
            cproc.ctxt.name = modname                       -- obvious
            cproc.ctxt.sync = sync                          -- response channel
            if newmod then
                if type(newmod.init) ~= "function" then
                    status = "module '" .. modname .. "' has no 'init' function"
                    newmod = nil
                else
                    M.bindenv(newmod.init)                          -- set environment translation for init function
                    M.setglobal(sched.curproc,menv)                 -- bind current proc to new app env
                end
            end        
        end
        return newmod, status
    end        
        
    return self
end

local kmod = share('mod',mod.new(), loaded)

-- module context control --

-- initializer creates global env space for an app proc
function M.setglobal(iproc,...)
    local args = {...}
    local menv = args[1] or env.safe() 
    debug.setfenv(iproc.co, menv)       -- set the default runtime env to the app env
    -- initialize the context and expose loader interface
    iproc.ctxt.env = menv
    -- the only thing an app can't import is import, so expose that
    iproc.ctxt.env.import = kmod.import
end

-- this sets the global environment for 'startfun'
function M.bindenv(startfun)
    setfenv(startfun, init_proxy)                -- proxy the start function into the active global env
end
   

--[[
        
        Kernel Startup

]]--

-- start kernel with first application module
function M.start()
    -- create a lua 'process' for init and ready it
    M.sched.start(n9,procs)
end


return M

