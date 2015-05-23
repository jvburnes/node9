-- apptest.lua --

-- this tests the shell cmd startup functions to make sure that the following features are operating properly
--
--    o  the global name space is clean
--    o  stdin,stdout,stderr are all functional
--    o  argv is being passsed properly
--    o  the pid, module name and result code are sent back properly
--

loadtime_num = 31415
loadtime_str = "now is the time"

function init(argv)
    local sys = import("sys")
    local buffers = import("buffers")
    local mybuff = buffers.new(1024)
    local stdin = sys.fildes(0)
    local stdout = sys.fildes(1)
    local stderr = sys.fildes(2)
    
    function fail(status,msg)
        sys.fprint(stderr, "apptest: %s\n", msg)
        error("fail: "..status)
    end

-- (0) test load-time name space
--
-- make sure load-time evaluations are set
    assert(loadtime_num == 31415, "assertion: loadtime number not properly set")
    assert(loadtime_str == "now is the time", "assertion: loadtime string not properly set")
--
-- (1) test global name space
--
--  __SHELL should not exist
    assert(not __SHELL, "assertion: __SHELL is set: globals are not private")
--  global write works
    myglobal = 271828
--  global read works
    assert(myglobal == 271828, "assertion: global read/write failed")
-- (2) test std streams
--
-- stdout is writable
    sys.fprint(stdout,"please enter your name\n")
-- stdin is readable
    sys.read(stdin,mybuff,80)
    local myname = mybuff.tostring()
    sys.fprint(stdout,"hello %s\n",myname)
-- stderr is writable and separate from stdout
-- will need to test with redirection system

    sys.fprint(stdout,"this is stdout\n")
    sys.fprint(stderr,"this is stderr\n")
    assert(stdin ~= stdout and stdin ~= stderr and stdout ~= stderr, "assertion: stdio descriptor error")
    
-- (3) test init interface
-- 
-- make sure argv[1] is the module name
    assert(argv[1] == "apptest", "assertion: module name not properly set")
-- make sure argv[2 .. numargs] are command argument strings
    assert(argv[2] == "1" and argv[3] == "2" and argv[4] == "3", "assertion: arguments 1 2 3 missing")

-- finally check the soft error function
    --fail("open error","no such device '#xxd'")
end
