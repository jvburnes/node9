usage = "unmount [source] target"

function fail(status, msg)
	sys.fprint(sys.fildes(2), "unmount: %s\n", msg);
	error("fail:" .. status)
end

function nomod(mod)
    fail("load", string.format("can't load %s: %s", mod, sys.errstr()))
end

function init(argv)
    sys = import("sys")
    buffers = import("buffers")    
    arg = import('arg')
    
    -- massage the argument list 
    
    if not arg then nomod('arg') end
    arg.setusage(usage)
    
    local opts = arg.getopt(argv,"")
    
    local argl = arg.strip()
    
    if #argl < 1 or #argl > 2 then arg.usage() end
    
    local target = table.remove(argl)
    
    local source = argl[1]
    
    -- and unmount
    local rc = sys.unmount(source, target)
    
    if rc < 0 then 
        fail("unmount", string.format("unmount failed because: %s", sys.errstr()))
    end
    
end

