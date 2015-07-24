-- the main binary
project "node9"
    -- is this kind of app
    kind "ConsoleApp"
    targetdir(_WORKING_DIR .. "/bin")
    
    -- NODE9 PROJECT DEFINITIONS --
    defines {"EMU"}
    
    -- Initialize build
    -- Snapshot the kernel build / time
    prebuildcommands {"src/styx/utils/ndate >src/include/kerndate.h"}
   
    -- primary kernel files --
    files {"main.c", "misc9.c", "styx/svcs/*.c",
      "styx/hosting/libuv/os-uv.c", "styx/hosting/libuv/emu.c"
    }

    -- files we're not building yet  
    removefiles {"styx/svcs/devprog.c", "styx/svcs/devprof.c", "styx/svcs/devdynld*.c", 
              "styx/svcs/dynld*.c",  "styx/svcs/ipif6-posix.c","styx/svcs/srv.c", 
              "styx/svcs/devsrv.c", "styx/svcs/devfs-posix.c" } 
    
    
    includedirs ({ "include", "styx/svcs" })
    
    links {"9", "bio", "sec"}
    -- currently it's important to group all statics together for gcc chain
    filter "not platforms:macosx"
        links {"luajit", "uv"}

        
    -- PLATFORM SPECIFICS --
    filter "platforms:linux"
        files { "styx/platform/Linux/os.c",
                "styx/platform/Linux/segflush-386.c",
                "styx/platform/Linux/cmd.c",
                "styx/platform/Linux/devfs.c",
                "styx/libs/lib9/getcallerpc-Linux-X86_64.s"
              }

        links {"dl", "m"}
        linkoptions {"-Wl,--export-dynamic"}

    filter "platforms:macosx"
        files { "styx/platform/MacOSX/os.c",
                "styx/platform/MacOSX/cmd.c",
                "styx/platform/MacOSX/devfs.c",
                "styx/libs/lib9/getcallerpc-MacOSX-X86_64.s"
              }
        
        links { "Carbon.framework", "CoreFoundation.framework", "IOKit.framework"}

        -- brain damage because you can't force osx linker to prefer statics
        -- without including them explicitly on the build line or preventing every possible
        -- sharable lib with the same name being findable
        prelinkcommands { "cd libuv/.libs; ln -sf libuv.a libuv_s.a; cd ../..; cd luajit/src; ln -sf libluajit.a libluajit_s.a; cd ../.." }
        links { "luajit_s", "uv_s" }
            
        linkoptions { "-pagezero_size 10000", "-image_base 100000000"}
        
    filter "platforms:freebsd"
        files { "styx/platform/FreeBSD/os.c",
                "styx/platform/FreeBSD/cmd.c",
                "styx/platform/FreeBSD/devfs.c",
                "styx/libs/lib9/getcallerpc-FreeBSD-X86_64.s"
              }

        links {"m", "kvm"}
        linkoptions {"-Wl,--export-dynamic"}
    
    filter "platforms:windows"
        files { "styx/platform/Nt/os.c",
                "styx/platform/Nt/cmd.c",
                "styx/platform/Nt/devfs.c",
                "styx/platform/Nt/r16.c",
              }
              
        includedirs "styx/platform/Nt"
        
        links {"m"} -- i think
        links {"netapi32", "wsock32", "user32", "gdi32", "advapi32", "winmm", "mpr"} -- orobably not current for win64

    filter "not platforms:windows"
        links {"pthread"}

    -- reset filters
    filter {} 


project "libnode9"
    -- is this kind of app
    kind "SharedLib"
    targetname "node9"
    targetdir(_WORKING_DIR .. "/lib")
    
    defines {"EMU"}
    files {"styx/svcs/node9.c", "styx/svcs/error.c" }
    links {"9", "bio", "sec"}
    filter "not platforms:windows"
        links {"pthread"}

    includedirs ({"include", "styx/svcs" })
    
    -- PLATFORM SPECIFICS --
    filter "platforms:macosx"      
        links { "Carbon.framework", "CoreFoundation.framework", "IOKit.framework" }
        linkoptions {"-undefined dynamic_lookup"}
        postbuildcommands {"rebase lib/libnode9.dylib"}
        
    -- reset filters
    filter {}
