--
-- demo startup shell
--

band = bit.band;
bor = bit.bor
brshift = bit.rshift

function testfs()
    local function cat(path)
        local catf = sys.open(path, sys.OREAD)
        if not catf then
            print("cat: could not open file")
            return
        end
        local dbuf = bufio.mkBuffer(512)
        while true do
            local nbytes = sys.read(catf, dbuf, 256)
            if nbytes == 0 then break end
            sys.print("%s",bufio.string(dbuf.data,dbuf.len))
        end
    end

    
    sys.print("\ninit: available devices are:\n")
    cat("/dev/drivers")

    sys.print("\ninit: the current cpu type is:\n")
    cat("/env/cputype")
    
    sys.print("\ninit: on host:\n")
    cat("/env/emuhost")

    -- just use a temp buf
    local bootbuf = bufio.mkBuffer(80)
    local bdate = os.date()  --safe?
    bufio.copy(bootbuf.data, bdate)
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
    local bbuff = bufio.mkBuffer(4096)
    sys.print("buffer allocated of size %d\n",bbuff.size)
    
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
            local fpos = sys.seek(bios, 0, sys.SEEKSTART) -- fpos should be a 64 bit boxed int (cdata)
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
            local auxbuf = bufio.mkBuffer(65536)

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
            local oldfpos = fpos
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

-- the demo 'dirtracker' task --

function dirtracker(path, sleeptime)
    local pid,appname = sys.id()
    sys.print("%d starting...\n",pid)
    -- main body
    for i=1,10 do
        local root = sys.open(path, sys.OREAD)
        if (root.fd < 0) then
            sys.print("pid(%d) could not open path '%s'\n",pid,path)
        else
            --sys.print("pid(%d) root is %s\n",pid,root)
        end
        -- display its directory contents
        do
            local need_hdr = true
            while true do
                local dirpack = sys.dirread(root)
                if dirpack.num == 0 then break end
                if need_hdr then
                    sys.print("\npid(%d): %s\n",pid,path)
                    sys.print("pid(%d): perms            uid          gid          size               atime           name\n",pid)
                    need_hdr = false
                end
                
                local dir = dirpack.dirs
                for i=0, dirpack.num-1 do
                    sys.print("pid(%d): %s\n",pid,dir)
                    dir = dir + 1
                end
             end
             --io.flush()
             sys.sleep(sleeptime)
        end
    end
    sys.print("pi is %f\n",pi)
    pi = pi - 1.0
    sys.print("my pid was %d\n",pid)
    last_result[pid] = pi
end

-- init: must be present in an executable module.  receives the 'sys' environment which contains 
--       system constants, system calls and argv

function init(argv)
    -- stupid simple init starts some child procs and exits after a few minutes
    sys = import("sys")
    bufio = import("bufio")
    
    local pid,appname = sys.id()
    
    sys.print("pid(%d) starting...\n",pid)
    pi = 3.1415926
    last_result = {}
    local myconsole = sys.open("#c/cons", sys.OWRITE)
    assert(myconsole, "ERROR: couldn't open console for write\n")

    sys.fprint(myconsole,"(%s): starting up, the time on the console is %s\n",argv[1],os.date())

    sys.print("\n\n\ninit: spawning dirtracker children\n")
    
    local taskA = sys.spawn(dirtracker,"/",314)
    local taskB = sys.spawn(dirtracker,"/fd",271)
    local taskC = sys.spawn(dirtracker,"/env",141)
    
    -- give the dirtracker demo time to run
    for i=1,10 do
        sys.sleep(1000)
        sys.print("\ninit: ****************************** TICK: %d ****************************\n",i);
    end
    
    -- run file system tests
    --testfs(sys)
    sys.print("pi is finally %f\n",pi)
    sys.print("sys.OWRITE is %d\n",sys.OWRITE)
    sys.print("OWRITE is %s\n",OWRITE)
    sys.print("the last results were...\n")
    for i,v in pairs(last_result) do
        sys.print("last result[%d] = %f\n",i,v)
    end
    
    testfs(sys)
    
    sys.print("checking for leaks\n")
    for i,v in pairs(sys.env()) do
        sys.print("    i: %s, v: %s\n",i,v)
    end
end
