-- the main binary
project "node9"
    -- is this kind of app
    kind "ConsoleApp"
    targetdir(_WORKING_DIR .. "/bin")
    
    -- NODE9 DEFINITIONS --
    defines { "EMU" }
    
    -- Initialize build
    -- Snapshot the kernel build / time
    prebuildcommands {"src/styx/utils/ndate >src/include/kerndate.h"}
   
    -- Build Dependencies First
    -- Make these platform independent.
    -- This is only for POSIX (do we use mingw on widows?)
    prebuildcommands {"cd libuv; sh autogen.sh; ./configure; make"}
    prebuildcommands {"cd luajit; make" }

    -- primary kernel files --
    files {"main.c", "misc9.c", "styx/svcs/*.c",
      "styx/hosting/libuv/os-uv.c", "styx/hosting/libuv/emu.c"
    }
    
    removefiles {"styx/svcs/devprog.c", "styx/svcs/devprof.c", "styx/svcs/devdynld*.c", 
              "styx/svcs/dynld*.c",  "styx/svcs/ipif6-posix.c","styx/svcs/srv.c", 
              "styx/svcs/devsrv.c" } 
    
    includedirs { _WORKING_DIR .. "/fs/module", "include", "styx/include", "styx/svcs", 
                  _WORKING_DIR .. "/libuv/include", _WORKING_DIR .. "/libuv/src", _WORKING_DIR .. "/luajit/src", 
                  "styx/hosting/libuv/include" }

    links {"9", "bio", "sec", "pthread" }
    
    -- PLATFORM SPECIFICS --
    filter "system:macosx"
        -- this is a hack because clang build chain doesn't know how to prioritize static libraries in front of dynamics
        prebuildcommands {"cp luajit/src/libluajit.a luajit/src/libluajit_s.a"}
        prebuildcommands {"cp libuv/.libs/libuv.a libuv/.libs/libuv_s.a"}

        files { "styx/platform/MacOSX/os.c",
                "styx/platform/MacOSX/cmd.c",
                "styx/platform/MacOSX/devfs.c"
                "styx/libs/lib9/getcallerpc-MacOSX-X86_64.s",
              }
        links { "Carbon.framework", "CoreFoundation.framework", "IOKit.framework",
                "luajit_s", "uv_s" }
            
        linkoptions { "-pagezero_size 10000", "-image_base 100000000"}
    
    filter "system:linux"
        files { "styx/platform/Linux/os.c",
                "styx/platform/Linux/cmd.c",
                "styx/platform/Linux/devfs.c"
                "styx/libs/lib9/getcallerpc-Linux-X86_64.s",
              }

    filter "system:not macosx"
        links { "luajit", "uv" }
        
    -- reset filters
    filter {} 

project "libnode9"
    -- is this kind of app
    kind "SharedLib"
    targetname "node9"
    targetdir(_WORKING_DIR .. "/lib")
    
    -- LOCAL EMULATOR DEFINES
    defines { "EMU" }

    files {"styx/svcs/node9.c", "styx/svcs/error.c" }
    links {"9", "bio", "sec", "pthread" }

    includedirs { _WORKING_DIR .. "/fs/module", "include",  "styx/include", "styx/svcs", 
         _WORKING_DIR .. "/libuv/include", _WORKING_DIR .. "/libuv/src", _WORKING_DIR .. "/luajit/src",
         "styx/hosting/libuv/include"}
    
    -- PLATFORM SPECIFICS --
    filter "system:macosx"      
        links { "Carbon.framework", "CoreFoundation.framework", "IOKit.framework" }
        linkoptions {"-undefined dynamic_lookup"}
        postbuildcommands {"rebase lib/libnode9.dylib"}
        
    -- reset filters
    filter {}
