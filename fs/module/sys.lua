local M = {}

local scall = import("syscall")
-- configure & cache call records
local s_open = sreq.open
local s_create = sreq.create
local s_dup = sreq.dup
local s_fildes = sreq.fildes
local s_seek = sreq.seek
local s_iounit = sreq.iounit
local s_read = sreq.read
local s_readn = sreq.readn
local s_pread = sreq.pread 
local s_write = sreq.write 
local s_pwrite = sreq.pwrite
local s_print= sreq.print
local s_fprint = sreq.fprint
-- local s_stream = sreq.stream
local s_stat = sreq.stat 
local s_fstat = sreq.fstat
local s_wstat = sreq.wstat 
local s_fwstat = sreq.fwstat
local s_dirread = sreq.dirread
-- local s_bind = sreq.bind
-- local s_mount = sreq.mount
-- local s_unmount = sreq.unmount
local s_remove = sreq.remove
local s_chdir = sreq.chdir
local s_fd2path = sreq.fd2path
--local s_pipe = sreq.pipe
--local s_dial = sreq.dial
local s_announce = sreq.announce
--local s_listen = sreq.listen
--local s_file2chan = sreq.file2chan
--local s_export = sreq.export
local s_sleep = sreq.sleep
--local s_fversion = sreq.fversion
--local s_fauth = sreq.fauth
--local s_pctl = sreq.pctl
local s_spawn = sreq.spawn

--
-- sys requests
--   
function M.open(path, mode) return scall.open(vproc, s_open, path, mode) end

function M.create(path, mode, perm) return scall.create(vproc, s_create, path, mode, perm) end

function M.dup(oldfd, newfd) return scall.dup(vproc, s_dup, oldfd, newfd) end

function M.fildes(fdnum) return scall.fildes(vproc, s_fildes, fdnum) end

function M.seek(fd, offset, start) return scall.seek(vproc, s_seek, fd, offset, start) end

function M.iounit(fd) return scall.iounit(vproc, s_iounit, fd) end

function M.read(fd, buf, nbytes) return scall.read(vproc, s_read, fd, buf, nbytes) end

function M.readn(fd, buf, nbytes) return scall.readn(vproc, s_readn, fd, buf, nbytes) end

function M.pread(fd, buf, nbytes, offset) return scall.pread(vproc, s_pread, fd, buf, nbytes, offset) end

function M.write(fd, buf, ...) return scall.write(vproc, s_write, fd, buf, ...) end

function M.pwrite(fd, buf, nbytes, offset) return scall.pwrite(vproc, s_pwrite, fd, buf, nbytes, offset) end

function M.sprint(fmt, ...) return string.format(fmt, ...) end

function M.print(fmt, ...) return scall.print(vproc, s_print, fmt, ...) end

function M.fprint(fd, fmt, ...) return scall.fprint(vproc, s_fprint, fd, fmt, ...) end
    
--[[ function M.stream(src, dst, bufsize) return scall.stream(vproc, s_stream, fmt, ...) end --]]
    

function M.stat(path) return scall.stat(vproc, s_stat, path) end

function M.fstat(fd) return scall.fstat(vproc, s_fstat, fd) end

function M.wstat(path, sdir) return scall.wstat(vproc, s_wstat, path, sdir) end

function M.fwstat(fd, sdir) return scall.fwstat(vproc, s_fwstat, fd, sdir) end

function M.dirread(fd) return scall.dirread(vproc, s_dirread, fd) end

function M.errstr() return scall.errstr(vproc) end

function M.werrstr(errstr) return scall.werrstr(vproc, errstr) end

--[[
function M.bind(name, old, flags) return scall.bind(vproc, s_bind, name, old, flags) end

function M.mount(FD, AFD, oldstring, flags, anamestring) return scall.mount(vproc, s_mount, FD, AFD, oldstring, flags, anamestring) end

function M.unmount(namestring, oldstring) return scall.unmount(vproc, s_unmount, namestring, oldstring) end
]]--    

function M.remove(path) return scall.remove(vproc, s_remove, path) end

function M.chdir(path) return scall.chdir(vproc, s_chdir, path) end

function M.fd2path(fd) return scall.fd2path(vproc, s_fd2path, fd) end

--[[
function M.pipe() return scall.pipe(vproc, s_pipe) end

function M.dial(addrstring, localstring) return scall.dial(vproc, s_dial, addrstring, localstring) end

function M.announce(addrstring) return scall.announce(vproc, s_announce, addrstring) end

function M.listen(connection) return scall.listen(vproc, s_listen, connection) end

function M.file2chan(dirstring, filestring) return scall.file2chan(vproc, s_file2chan, dirstring, filestring) end

function M.export(FD, dirstring, flags) return scall.export(vproc, s_export, FD, distring, flags) end
--]]    
function M.millisec() return n9.sys_millisec() end

function M.sleep(millisecs) return scall.sleep(vproc, s_sleep, millisecs) end
--[[    
function M.fversion(FD, bufsize, versionstring) return scall.fversion(vproc, s_fversion, FD, bufsize, versionstring) end

function M.fauth(FD, anamestring) return scall.fauth(vproc, s_fauth, FD, anamestring) end

function M.pctl(flags, movefd_list) scall.pctl(vproc, s_pctl, flags, movefd_list) end
]]--

function M.spawn(fun, name, ...) return scall.spawn(vproc, proc, s_spawn, fun, name, ...) end

-- support functions

function M.nulldir() return scall.stat.new(-1) end

function M.mkBuffer(size) return scall.mkBuffer(size) end

-- inherit the system constants
setmetatable(M, {__index = scall.const})

-- return the constructed module
return M
