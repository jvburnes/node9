--
-- node9 luaspace initialization
-- 
-- this function synthesizes the startup task (pid 1), makes it ready and transfers control to the scheduler

function bootmod(argv)
    -- first retrieve the runtime env
    local iproc = argv[2]
    -- import the shell into the current context and start
    -- it doesnt need a channel
    local sh,status = import('/appl/sh.lua',iproc.ctxt.env)
    
    if not sh then
        dprint("bootstrap/import fault:",status)
    else
        sh.init(argv)
    end
end

function init(nroot)
    _noderoot = nroot
    package.path = _noderoot .. "/os/init/?.lua;" .. _noderoot .. "/os/lib/?.lua;" .. package.path
    
    -- node9 lua kernel startup
    -- load primary kernel functions
    local kern = require 'kernel'
    -- synthesize the init task (pid 1) as root proc
    local ivproc = kern.gen_vproc(nil)                  -- create a base vproc
    local iproc = kern.proc.new(bootmod, ivproc)        -- create proc 
    iproc.ctxt = {}
    iproc.ctxt.loaded = {}
    iproc.ctxt.name = "/appl/sh.lua"
    -- generate an application context
    kern.bindenv(bootmod)                               -- set custom env lookup for bootstrap function
    kern.setglobal(iproc)                               -- create and bind a new global env space for the initial app process
    
    -- register the contained vproc /w the GC (hacky)
    iproc.collect()
    
    -- setup the boot args and schedule the boot task
    iproc.args = {"/appl/sh",iproc}
    iproc.ctxt.argv = iproc.args
    
    kern.sched.ready(iproc)
    kern.start()
end
