-- scheduler: roundrobin

M = {}
M.curproc = nil

local rdyq = {}
local runq = {}

function M.ready(proc)
    rdyq[#rdyq+1] = proc
end


-- scheduler startup: n9 is C kernel iface, procs is proc table
function M.start(n9,procs)

    -- resumes proc coroutine and handles exiting processes 
    -- returns true (or gen output) if proc still running or
    -- false if proc has exited
    function resume(proc)
        local xeq, gen
        M.curproc = proc            -- set context
        local bootargs = proc.args
        -- task bootstrapping.  argv (for init) or arglist for normal task
        if bootargs then 
            proc.args = nil
            if bootargs == proc.ctxt.argv then
                xeq, gen = coroutine.resume(proc.co, bootargs)
            else
                xeq, gen = coroutine.resume(proc.co, unpack(bootargs))
            end
        else
            xeq, gen = coroutine.resume(proc.co)
        end
        --io.write("node9/sched: exited proc: xeq: ",xeq,", gen: '",gen,"'"); io.flush()
        local term = false
        if xeq == false or coroutine.status(proc.co) == "dead" then term = true end
        
        -- error/abort processing
        local errstr = ""
        if term then
            -- process has aborted or has exited
            -- if a sync channel exists, report termination and any error
            -- if this is an application, terminate any child procs (process group members)
            if xeq == false then
                -- soft error and abort msg processing
                -- get the msg after the second colon (hack!)
                local lstart = string.find(gen, ":")
                local lend = string.find(gen,":",lstart+1)
                local errline = string.sub(gen,lstart+1,lend-1)
                errstr = string.sub(gen,lend + 2)
                -- we should do something more sophisticated and kill off child procs for apps
                if string.sub(errstr,1,5) ~= "fail:" then
                
                -- hack up an exit error string.  sucks because coroutine.resume doesnt allow custom errs
                -- also sucks because there's no guarantee that coroutine err formats are stable
                    errstr = "module '" .. proc.ctxt.name .. "' aborted at line: " .. errline .. ", '" .. errstr .. "'"
                end
            else
                --print("application",proc.ctxt.name,"has terminated normally")
            end

            -- notify anyone listening
            if proc.ctxt.sync then
                proc.ctxt.sync.send({proc.pid, proc.ctxt.name, errstr})
            end
            
            if proc.pid == 1 and errstr ~= "" then
                print("init process faulted: " .. errstr)
            end
            
            -- remove remaining proc references and let it go
            -- (probably should hold for a while to resolve zombies)
            M.curproc = nil
            procs[proc.pid] = nil
            
            if proc.pid == 1 then
                return false
            end
        else      
            -- otherwise it's still running, so take care of bookkeeping
            -- waiting for completion or next quanta
            if gen then
                proc.status = "yielded"
                M.ready(proc)
            else
                proc.status = "waiting"
            end
        end
        -- feed generated output up, or just the continuation status
        return gen or xeq
    end

    -- main scheduler logic --
    -- separate this from resume and ready logic
    while true do
        -- make all completed requesters ready
        local count = 0
        
        -- two runnable queues:
            -- all pids in the reply queue and
            -- all procs in the rdy queue
        
        -- first run any proc with a pid in the reply queue            
         while true do
            -- check who the next reply is for
            local wait_pid = n9.sysrep()
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
        for _, rproc in pairs(runq) do
            if not resume(rproc) then
                return
            end
        end
            
        -- release anything still in the runq (including old procs)
        runq = nil
        
        -- process new i/o and timer events and come back right away if runnable procs
        n9.svc_events(#rdyq)
    end
end
    
return M

