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
   
    -- primary kernel files --
    files {"main.c", "misc9.c", "styx/svcs/*.c",
      "styx/hosting/libuv/os-uv.c", "styx/hosting/libuv/emu.c"
    }

    --buildoptions {"-v"}    
    removefiles {"styx/svcs/devprog.c", "styx/svcs/devprof.c", "styx/svcs/devdynld*.c", 
              "styx/svcs/dynld*.c",  "styx/svcs/ipif6-posix.c","styx/svcs/srv.c", 
              "styx/svcs/devsrv.c", "styx/svcs/devfs-posix.c" } 
    includedirs ({ _WORKING_DIR .. "/fs/module", "include", "styx/include", "styx/svcs", 
                  _WORKING_DIR .. "/libuv/include", _WORKING_DIR .. "/libuv/src", _WORKING_DIR .. "/luajit/src", 
                  "styx/hosting/libuv/include" })

    links {"9", "bio", "sec", "pthread", "luajit", "uv" }
    
    -- PLATFORM SPECIFICS --
    filter "system:macosx"
        files { "styx/platform/MacOSX/os.c",
                "styx/platform/MacOSX/cmd.c",
                "styx/platform/MacOSX/devfs.c",
                "styx/libs/lib9/getcallerpc-MacOSX-X86_64.s"
              }
        
        links { "Carbon.framework", "CoreFoundation.framework", "IOKit.framework"}
            
        linkoptions { "-pagezero_size 10000", "-image_base 100000000"}
        
    
    filter "system:linux"
        files { "styx/platform/Linux/os.c",
                "styx/platform/Linux/segflush-386.c",
                "styx/platform/Linux/cmd.c",
                "styx/platform/Linux/devfs.c",
                "styx/libs/lib9/getcallerpc-Linux-X86_64.s"
              }

        -- MAKE SURE THIS IS EXECUTED --
	links {"dl", "m"}
        linkoptions {"-Wl,--export-dynamic"}

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

    includedirs ({ _WORKING_DIR .. "/fs/module", "include",  "styx/include", "styx/svcs", 
         _WORKING_DIR .. "/libuv/include", _WORKING_DIR .. "/libuv/src", _WORKING_DIR .. "/luajit/src",
         "styx/hosting/libuv/include"})

    
    -- PLATFORM SPECIFICS --
    filter "system:macosx"      
        links { "Carbon.framework", "CoreFoundation.framework", "IOKit.framework" }
        postbuildcommands {"rebase lib/libnode9.dylib"}
        linkoptions {"-undefined dynamic_lookup"}
        
    -- reset filters
    filter {}
