-- the main binary
project "node9"
    -- is this kind of app
    kind "ConsoleApp"
    targetdir(_WORKING_DIR .. "/bin")

    -- INITIAL BUILD ENVIRONMENT
    -- snapshot the kernel build / time
    -- Build Dependencies First
    prebuildcommands {"cd ../libuv; make; cd ../luajit; make; cd ../src" }
    
    -- this is a hack because clang build chain doesn't know how to prioritize static libraries in front of dynamics
    prebuildcommands {"cp ../luajit/src/libluajit.a ../luajit/src/libluajit_s.a"}
    prebuildcommands {"cp ../libuv/.libs/libuv.a ../libuv/.libs/libuv_s.a"}

    prebuildcommands {"styx/utils/ndate >include/kerndate.h"}

    -- LOCAL EMULATOR DEFINES
    defines { "EMU" }
    
    -- -- Kernel init and drivers -- --
    files {"main.c", "misc9.c", "styx/svcs/*.c",
      "styx/platform/MacOSX/os.c", "styx/hosting/libuv/os-uv.c", "styx/hosting/libuv/emu.c",
      "styx/libs/lib9/getcallerpc-MacOSX-X86_64.s",
      "styx/platform/MacOSX/cmd.c", "styx/platform/MacOSX/devfs.c"} -- "styx/hosting/libuv/asm-386.s",
  
      excludes {"styx/svcs/devprog.c", "styx/svcs/devprof.c", "styx/svcs/devdynld*.c", "styx/svcs/dynld*.c",
      "styx/svcs/ipif6-posix.c","styx/svcs/srv.c", "styx/svcs/devsrv.c" } 

    includedirs { _WORKING_DIR .. "/fs/module", "include", "styx/include", "styx/svcs", 
        _WORKING_DIR .. "/libuv/include", _WORKING_DIR .. "/libuv/src", _WORKING_DIR .. "/luajit/src", 
        "styx/hosting/libuv/include" }

    links { "Carbon.framework", "CoreFoundation.framework", "IOKit.framework",
            "pthread",  "9", "bio", "sec",  "luajit_s", "uv_s" } 
    linkoptions { "-pagezero_size 10000", "-image_base 100000000", "-lm", "-v"}

project "libnode9"
    -- is this kind of app
    kind "SharedLib"
    targetname "node9"
    targetdir(_WORKING_DIR .. "/lib")
    
    -- LOCAL EMULATOR DEFINES
    defines { "EMU" }

    files {"styx/svcs/node9.c", "styx/svcs/error.c" }

    includedirs { _WORKING_DIR .. "/fs/module", "include",  "styx/include", "styx/svcs", 
         _WORKING_DIR .. "/libuv/include", _WORKING_DIR .. "/libuv/src", _WORKING_DIR .. "/luajit/src",
         "styx/hosting/libuv/include"}
    
    links { "Carbon.framework", "CoreFoundation.framework", "IOKit.framework",
            "pthread", "9", "bio", "sec" } 
    linkoptions {"-undefined dynamic_lookup", "-lm", "-v"}
 
    -- OSX specific 
    postbuildcommands {"rebase " .. _WORKING_DIR .. "/lib/libnode9.dylib"}
