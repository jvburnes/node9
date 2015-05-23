function split(s,re)
    local res = {}
    local t_insert = table.insert
    re = '[^'..re..']+'
    for k in s:gmatch(re) do t_insert(res,k) end
    return res
end

-- these should be app-wide
function cd(path)
    sys.chdir(path)
end

__SHELL = "/appl/sh"

function ls(path)
    local lpath = path or "."
    local rc,sdir = sys.stat(lpath)
    if rc ~= 0 then
        sys.print("ls: No such file or directory: '%s'\n",path)
        return
    end
    if bit.band(sdir.mode,sys.DMDIR) == 0 then
        sys.print("%s\n",sdir)
    else
        local ldir = sys.open(lpath, sys.OREAD)
        if (ldir.fd < 0) then
            sys.print("ls: could not open path '%s'\n",lpath)
        end
        -- display its directory contents
        while true do
            local dirpack = sys.dirread(ldir)
            if dirpack.num == 0 then break end
            
            local dir = dirpack.dirs
            for i=0, dirpack.num-1 do
                sys.print("%s\n",dir)
                dir = dir + 1
            end
        end
    end
end

function cat(path)
    local catf = sys.open(path, sys.OREAD)
    if not catf then
        sys.print("cat: could not open file '%s'\n",path)
        return
    end
    local dbuf = buffers.new(2048)
    while sys.read(catf, dbuf, 2048) ~= 0 do
        sys.print("%s",dbuf.tostring())
    end
end


function init(argv)
    sys = import("sys")
    buffers = import("buffers")
    

    -- get a copy of the execution env (probably should have independent one to keep scripts from screwing with sh state)
    local sysenv =sys.env()
    local done = false

    -- evalstring attempts to evaluate lstr in the current shell environment
    -- it first tries to execute it as an expression (using return),
    -- if that doesn't work, it will try to evaluate it as an lexpr statement
    -- returns: status=true, successful evaluation and 'result' contains result (side effects can occurr)
    --          status=false, could not be properly evaluated, error is in 'result'
    -- (this is convoluted because we have to avoid double execution side effects)
    local function evalstring(lstr)
        local result = nil
        local syntax = nil
        local semant = nil
        local eval, status = loadstring("return " .. lstr)
        if eval then
            -- its syntactially consistent with an expression
            setfenv(eval,sysenv)
            -- try to execute
            semant, result = pcall(eval)
            status = semant
            -- if it executed properly
              -- and it looks like a function call
                -- and its name evaluates to a function that returns values as side effects to their output functions
                  -- then just absorb the side effect return value by setting result to nil
                  -- (they can always capture it if they want it by using an assignment)
            --
        end
        if not eval or not result then
            -- not meaningful or ambiguous as a pure expr, try it as an lexpr/statement
            local seval, sstatus = loadstring(lstr)
            if not seval then
                -- its not meaningful as a standalone chunk
                -- if it originally evaluated as an expr with a nil result, it's undefined
                if eval then 
                    result = "variable '" .. lstr .. "' is undefined"
                else
                    -- else it's just a syntax error
                    result = sstatus
                end
                status = false
            else
                if not eval then
                    -- it looks like a chunk, so execute it
                    setfenv(seval, sysenv)
                    semant, result = pcall(seval)
                    status = semant
                end
            end
        end
        return status, result
    end
    
    function runsync(app, dir)
        -- create a sync channel for the app
        app.sync = sys.Channel()
        -- wait on its control channel for process complete status
        -- return status, result
        return unpack(app.sync.recv())
    end
    
    -- links to the async app with a background channel
    function runasync(app, dir)
        -- create the background channel for the app
        app.sync = sys.Channel()
        -- return value is ok
        return 0, ""
    end
    
    -- extenal application bootstrap code for 'init'
    function runexternal(argv,apath,appdir,sync)
        -- load the app module into a fresh context
        -- place the thread into a NEWFD context with std streams copied
        local pid = sys.pctl(sys.NEWFD, {0,1,2})
        local mname = argv[1]
        local errstr = ""
        local newmod, mstat
        local error = error 
        local dprint = dprint
                
        -- attempt to import as an application
        newmod, mstat = import(apath, {}, sync)

        if not newmod then
            local lstart = string.find(mstat, ":")
            local lend = string.find(mstat,":",lstart+1)
            local errline = string.sub(mstat,lstart+1,lend-1)
            local errstr = string.sub(mstat,lend + 2)            
            sys.fprint(sys.fildes(2),"sh; module '%s' load failure at line %d: %s\n",apath,errline,errstr)
        else
            newmod.init(argv)
        end
    end

    -- startup

    -- first get a new FD env
    sys.pctl(sys.FORKFD)
    
    local lbuf = buffers.new(256)
  
    local cons = sys.open("#c/cons", sys.ORDWR)
    assert(cons, "ERROR: couldn't open console for write\n")
    sys.fprint(cons,"(%s): started\n[the time on the console is %s]\n",argv[1],os.date())

    -- process command line options
    
    -- run any startup script
    local lasterr, l_errstr
    
    -- REPL
    repeat 
        sys.fprint(cons,"; ")
        -- read
        llen = sys.read(cons, lbuf, 254)
        if llen > 0 then  -- includes EOL
            if llen > 1 then 
                local lstring = lbuf.tostring():sub(1,-2)
                -- first -- is it a command?
                if string.sub(lstring, 1, 1) ~= ' ' then
                    -- it's some sort of command
                    local asyncmode = false
                    local ok = false
                    -- split the command into arg lists
                    local argv = split(lstring," ")
                    
                    -- set sync or background mode
                    if #argv > 1 and argv[#argv] == '&' then
                        asyncmode = true
                        argv[#argv] = nil
                    elseif #argv[#argv] > 1 and argv[#argv]:sub(-1) == '&' then
                        asyncmode = true
                        argv[#argv] = argv[#argv]:sub(1,-2)
                    end
                    
                    local args = {}
                    
                    -- remove the command name and quote the args
                    for i=2,#argv do
                        table.insert(args, "'" .. argv[i] .. "'")
                    end
                        
                    -- builtin functions have precedence, so try that first
                    -- (can be overridden using absolute path)
                    local status,result = evalstring(argv[1] .. '(' .. table.concat(args,",") .. ')')
                    if not status then
                        -- try one more time as a loadable app
                        -- look for the app in the default places
                        -- (either /appl/<name>.lua or /appl/<name>/<name>.lua)
                        local appdir = false
                        local found = false
                        local apath = "/appl/" .. argv[1] .. ".lua"
                        if sys.stat(apath) == 0 then
                            found = true
                        else
                            apath = "/appl/" .. argv[1] .. "/" .. argv[1] .. ".lua"
                            if sys.stat(apath) == 0 then
                                found = true
                                appdir = true
                            end
                        end
                        
                        if found then
                            ok = true
                            -- eventually we will need to provide for mapping stdio pipes to 
                            -- applications for job control under async conditions
                            -- also pipelines will have to be supported
                            -- just run external for now
                            local sync = sys.Channel()
                            if appdir then dprint("run module uses app directory:",appdir) end
                            sys.spawn(runexternal,argv,apath,appdir,sync)
                            -- normally we would wait on the /prog/<pid>/'wait' fd for completion
                            -- but for testing we'll just wait on the proc.sync channel
                            -- (proc.sync is usually only for pid discovery)
                            local pid, mname, errstr = unpack(sync.recv())
                            -- if errstr begins with "fail:" then its just a status message
                            -- else its a module abort
                            if errstr == "" then
                                lasterr = ""
                            else
                                if string.sub(errstr,1,5) == "fail:" then
                                    lasterr = string.sub(errstr,6)
                                else
                                    lasterr = "module abort"
                                    sys.print("%s\n",errstr)
                                end
                            end
                            
                         end
                         
                         if not ok then
                            l_errstr = result
                            sys.print("unknown command, load error or bad option(s)\n")
                         end
                    else
                        if result then sys.print("%s\n",result) end
                    end
                else   -- its an immediate mode statement (apparently) 
                    -- eval
                    local estr = string.sub(lstring, 2)
                    local status, result = evalstring(estr)
                    if not status then
                        l_errstr = result
                    end
                    -- print
                    if result then 
                        sys.fprint(cons,"%s\n",result)
                    end
                end
            end
        else
            sys.fprint(cons,"^D\n")
            done = true
        end
    until done
end
