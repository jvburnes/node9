--
-- simple ls function
--
function init(argv)
    
    sys = import('sys')
    local path = argv[2] or "."
    
    local ldir = sys.open(path, sys.OREAD)
    
    if (ldir.fd < 0) then
        sys.print("ls: could not open path '%s'\n",path)
    else

    local need_hdr = true
    while true do
        local dirpack = sys.dirread(ldir)
        if dirpack.num == 0 then break end
        if need_hdr then
            sys.print("\n%s\n",path)
            sys.print("perms            uid          gid          size               atime           name\n")
            need_hdr = false
        end
        
        local dir = dirpack.dirs
        for i=0, dirpack.num-1 do
            sys.print("%s\n",dir)
            dir = dir + 1
        end
     end
end
