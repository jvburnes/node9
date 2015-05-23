--
-- export part of current namespace to a client connection
--
-- this is an extended version of export:
--      - if data-path is specified, its assumed to be the data connection from a listen circuit
--      - if add is specified, it's assumed to be an address spec to announce and listen for connections on
--      - if niether is specified, it's assumed that we were executed by a listen and need to read from stdin pipe
usage = "export [-a] dir [data-path | addr]"
stderr = nil

function fail(status, msg)
	sys.fprint(stderr, "export: %s\n", msg);
	error("fail:" .. status)
end

function nomod(mod)
    fail("load", string.format("can't load %s: %s", mod, sys.errstr()))
end

function init(argv)
    sys = import('sys')
    arg = import('arg')
    if not arg then nomod('arg') end
    
    arg.setusage(usage)
    stderr = sys.fildes(2)
    local opts = arg.getopt(argv,"")
    
    flag = sys.EXPWAIT
    
    for opt, val in pairs(opts) do
        if opt == "a" then
            flag = sys.EXPASYNC 
        else
            arg.usage()
        end
    end
            
    -- get a copy of just the arguments without names or options
    local cmdargs = arg.strip()
    
    n = #cmdargs
    
	if n < 1 or n > 2 then
		arg.usage()
    end
    
	local fd
    
    -- where do we listen?
	if n == 2 then
        -- on a specific connection or interface
        -- is it a connection?
        local rc = sys.stat(cmdargs[2])
        local data_path
        if rc ~= 0 then
            -- it's not a data connection, try it as an address
            -- announce it
            local astat, aconn = sys.announce(cmdargs[2])
            if not astat then
                fail("announce", string.format("can't announce on address %s: %s\n",cmdargs[2], sys.errstr()))
            end    
            -- listen on it
            local lstat, lconn = sys.listen(aconn)
            if not lstat then
                fail("listen",string.format("can't listen on address %s: %s\n",cmdargs[2], sys.errstr()))
            end
            -- someone connected so construct the data circuit path 
            data_path = ffi.string(lconn.dir) .. "/data"
        else
            data_path = cmdargs[2]
        end
        
        -- at this point we have a data path for the new connection
        fd = sys.open(data_path, sys.ORDWR)            -- open the data circuit
        if not fd then
            fail("open", string.format("can't open data connection %s: %s\n",data_path, sys.errstr()))
        end
    else
        -- no specific data path, so export on stdin
        fd = sys.fildes(0)
    end
    
    -- do the export
	rc = sys.export(fd, cmdargs[1], flag) 
    if rc < 0 then
		fail("export", string.format("can't export: %s\n", sys.errstr()))
	end
end
