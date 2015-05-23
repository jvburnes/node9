--
-- mount remote namespace onto a place in current namespace
--
--[[
include "sys.m";
	sys: Sys;
include "draw.m";
include "keyring.m";
include "security.m";
include "factotum.m";
include "styxconv.m";
include "styxpersist.m";
include "arg.m";
include "sh.m";
--]]


verbose = false
doauth = true
do9 = false
oldstyx = false
persist = false
showstyx = false
quiet = false
flags = 0

alg = "none"
keyfile = nil
spec = nil
addr = nil

usage = "mount [-a|-b] [-coA9] [-C cryptoalg] [-k keyfile] [-q] net!addr|file|{command} mountpoint [spec]"


function split(s,re)
    local res = {}
    local t_insert = table.insert
    re = '[^'..re..']+'
    for k in s:gmatch(re) do t_insert(res,k) end
    return res
end


function fail(status, msg)
	sys.fprint(sys.fildes(2), "mount: %s\n", msg);
	error("fail:" .. status)
end

function nomod(mod)
	fail("load", sys.sprint("can't load %s: %r", mod));
end

function netmkaddr(addr, net, svc)
	if not net then net = "net" end
    
	local adr = split(addr, "!")
    
	if #adr <= 1 then 
		if not svc then return string.format("%s!%s", net, addr) end
		return string.format("%s!%s!%s", net, addr, svc)
	end
    
	if not svc or #adr > 2 then return addr end
	return string.format("%s!%s", addr, svc)
end

function connect(dest)
	--if dest ~= nil and dest:sub(1,1) == '{' and dest:sub(#dest) == '}' then
		--if(persist)
			--fail("usage", "cannot persistently mount a command");
		--doauth = false;
		--return popen(ctxt, dest :: nil);
	--end
	local dst = split(dest, "!")
	if #dst == 1 then 
		fd = sys.open(dest, sys.ORDWR)
		if fd then
			--if(persist)
				--fail("usage", "cannot persistently mount a file");
			return fd
        end
		if dest:sub(1,1) == '/' then
			fail("open failed", string.format("can't open %s: %s", dest, sys.errstr()))
        end
	end
    
	local svc = "styx"
	if do9 then svc = "9fs" end
    
	local ndest = netmkaddr(dest, "net", svc)
    
	--if(persist){
	--	styxpersist := load Styxpersist Styxpersist->PATH;
	--	if(styxpersist == nil)
	--		fail("load", sys->sprint("cannot load %s: %r", Styxpersist->PATH));
	--	sys->pipe(p := array[2] of ref Sys->FD);
	--	(c, err) := styxpersist->init(p[0], do9, nil);
	--	if(c == nil)
	--		fail("error", "styxpersist: "+err);
	--	spawn dialler(c, ndest);
	--	return p[1];
	--}
    
	ok, c = sys.dial(ndest, nil)
    
	if ok < 0 then
        fail("dial failed",  string.format("can't dial %s: %s", ndest, sys.errstr()))
    end
    
	return c.dfd;
end

function user()
	local fd = sys.open("/dev/user", sys.OREAD)
    
	if not fd then return "" end

	local buf = buffers.new(sys.NAMEMAX)
    
	n = sys.read(fd, buf, buf.len)
    
	if n < 0 then return "" end

    return buf.tostring()
end

--[[
function authenticate(keyfile, alg,  dfd, addr)
	local cert, err

	local kr = import('keyring')
	if not kr then return nil, string.format("cannot import 'keyring': %s", sys.errstr()) end

	kd = "/usr/" .. user().. "/keyring/"
    
	if not keyfile then
		cert = kd .. netmkaddr(addr, "tcp", "")
		ok, _ = sys.stat(cert)
		if (ok < 0) then cert = kd + "default" end
	elseif #keyfile > 0 and keyfile:sub(1,1) ~= '/' then
		cert = kd .. keyfile
	else
		cert = keyfile
    end
    
	local ai = kr.readauthinfo(cert)
    if not ai then return nil, string.format("cannot read %s: %r", cert, sys.errstr()) end

	local auth = import('auth')
	if not auth then nomod('auth') end

	local fd
	fd, err = auth.client(alg, ai, dfd)
    
	if not fd then return nil, "authentication failed: " .. err end
	return fd, err
end
]]--

--[[
function dialler(dialc: chan of chan of ref Sys->FD, dest: string)
	while((reply := <-dialc) != nil){
		if(verbose)
			sys->print("dialling %s\n", addr);
		(ok, c) := sys->dial(dest, nil);
		if(ok == -1){
			reply <-= nil;
			continue;
		}
		(fd, err) := authcvt(c.dfd);
		if(fd == nil && verbose)
			sys->print("%s\n", err);
		# XXX could check that user at the other end is still the same.
		reply <-= fd;
	}
}

]]--
function authcvt(fd)
	local err,nfd
	if doauth then
		--nfd, err = authenticate(keyfile, alg, fd, addr);
		--if nfd == nil then return nil, err end
		--if verbose then sys.print("remote username is %s\n", err) end
        --return nfd,nil
        fail("not implemented","authentication is not currently implemented")
	end
	--if oldstyx then return cvstyx(fd) end
	return fd, nil
end

--[[
function popen(ctxt: ref Draw->Context, argv: list of string): ref Sys->FD
	sh := load Sh Sh->PATH;
	if(sh == nil)
		nomod(Sh->PATH);
	sync := chan of int;
	fds := array[2] of ref Sys->FD;
	sys->pipe(fds);
	spawn runcmd(sh, ctxt, argv, fds[0], sync);
	<-sync;
	return fds[1];
end

function runcmd(sh: Sh, ctxt: ref Draw->Context, argv: list of string, stdin: ref Sys->FD, sync: chan of int)
	sys->pctl(Sys->FORKFD, nil);
	sys->dup(stdin.fd, 0);
	stdin = nil;
	sync <-= 0;
	sh->run(ctxt, argv);
end

function cvstyx(fd: ref Sys->FD): (ref Sys->FD, string)
	styxconv := load Styxconv Styxconv->PATHNEW2OLD;
	if(styxconv == nil)
		return (nil, sys->sprint("cannot load %s: %r", Styxconv->PATHNEW2OLD));
	styxconv->init();
	p := array[2] of ref Sys->FD;
	if(sys->pipe(p) < 0)
		return (nil, sys->sprint("can't create pipe: %r"));
	spawn styxconv->styxconv(p[1], fd);
	p[1] = nil;
	return (p[0], nil);
end
]]--

--[[
function kill(pid: int)
	if ((fd := sys->open("#p/" + string pid + "/ctl", Sys->OWRITE)) != nil)
		sys->fprint(fd, "kill");
end


function styxlog(fd)
	if showstyx then
		--sys->pipe(p := array[2] of ref Sys->FD);
		--styx = load Styx Styx->PATH;
		--styx->init();
		--spawn tmsgreader(p[0], fd, p1 := chan[1] of int, p2 := chan[1] of int);
		--spawn rmsgreader(fd, p[0], p2, p1);
		--fd = p[1];
	end
	return fd
end

function tmsgreader(cfd, sfd: ref Sys->FD, p1, p2: chan of int)
	p1 <-= sys->pctl(0, nil);
	m: ref Tmsg;
	do{
		m = Tmsg.read(cfd, 9000);
		sys->print("%s\n", m.text());
		d := m.pack();
		if(sys->write(sfd, d, len d) != len d)
			sys->print("tmsg write error: %r\n");
	} while(m != nil && tagof(m) != tagof(Tmsg.Readerror));
	kill(<-p2);
end

function rmsgreader(sfd, cfd: ref Sys->FD, p1, p2: chan of int)
	p1 <-= sys->pctl(0, nil);
	m: ref Rmsg;
	do{
		m = Rmsg.read(sfd, 9000);
		sys->print("%s\n", m.text());
		d := m.pack();
		if(sys->write(cfd, d, len d) != len d)
			sys->print("rmsg write error: %r\n");
	} while(m != nil && tagof(m) != tagof(Tmsg.Readerror));
	kill(<-p2);
end
]]--

function nomod(mod)
    fail("load", string.format("can't load %s: %s", mod, sys.errstr()))
end

function init(argv)
    sys = import("sys")
    buffers = import("buffers")    
    arg = import('arg')
    
    if not arg then nomod('arg') end
    arg.setusage(usage)
    
    local opts = arg.getopt(argv,"fCk")
        
    for opt, val in pairs(opts) do
        if opt == 'a' then
            flags = bit.bor(flags, sys.MAFTER)
        elseif opt == 'b' then
            flags = bit.bor(flags, sys.MBEFORE)
        elseif opt == 'c' then 
            flags = bit.bor(flags, sys.MCREATE)
        elseif opt == 'C' then
            alg = val
        elseif opt == 'k' or opt == 'f' then
            keyfile = val
        elseif opt == 'A' then
            doauth = false
        elseif opt == '9' then
            doauth = false
            do9 = true
        elseif opt == 'o' then
            oldstyx = true
        elseif opt == 'v' then
            verbose = true
        elseif opt == 'P' then
            persist = true
--        elseif opt == 'S' then
--            showstyx = true
        elseif opt == 'q' then
            quiet = true
        else
            arg.usage()
        end
    end
    
    local argl = arg.strip()
    
    if #argl ~= 2 then
        if #argl ~= 3 then
            arg.usage()
        end
        spec = argl[3]
    end
    
    
    addr = argl[1]
    mountpoint = argl[2]
    
    --dprint("connecting addr '" .. addr .. "' to mountpoint '" .. mountpoint .. "'")
    if oldstyx and do9 then
        fail("usage","usage: cannot combine -o and -9 options")
    end
    
    local fd = connect(addr)
    
    local ok
    
    if do9 then
        --fd = styxlog(fd)
        --factotum = import("factotum")
        --if not factotum then
            --nomod("factotum")
        --end
        --ok = factotum.mount(fd, mountpoint, flags, spec, keyfile)
        fail("not implemented","factotum authentication not implemented")
    else
        local err
        if not persist then
            fd, err = authcvt(fd)
            if not fd then
                error(err)
            end
        end
        --fd = styxlog(fd)
        ok = sys.mount(fd, nil, mountpoint, flags, spec)
    end
    
    if ok < 0 and not quiet then
        error("mount failed: " .. ok)
    end    
end
