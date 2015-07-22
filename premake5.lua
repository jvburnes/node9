--[[
    node9 build configuration: the output of premake5 on this is a
                               multiplatform Makefile
  
    When you invoke 'premake gmake' you just tell premake to build a makefile for gmake. 
    If you have gmake on Windows, MacOS and Linux, you can use premake gmake for all
    platforms. It's when you actually build that you just need to specify your configuration
    and platform, ie: "gmake config=<config_type>_<platform type>"
    (on gcc-native systems like Linux and NetBSD, gmake is just 'make')
]]--

    -- get a stable build OS type
    -- "server" can change
    -- "platform" is the user selected target type
    local syshost = "unknown"
    local ver = os.getversion()
    local hosttype = ver.description
    
    if hosttype:sub(1,5) == "Linux" then
        syshost = "Linux"
    elseif hosttype:sub(1,8) == "Mac OS X" then
        syshost = "MacOSX"
    elseif hosttype:sub(1,7) == "Windows" then
        syshost = "Nt"
    else
        syshost = hosttype
    end
      
    defines ({"SYSHOST=" .. syshost})
    
    print(">>> Building Node9 solutions on OS '" .. syshost .. "' <<<")
   
    solution "node9-hosted"
    language "C"
    
    -- deployment configurations
    configurations { "debug", "devel", "release"}
    
    -- supported platforms (all 64 bit)
    platforms {
        "linux",
        "macosx",
        "freebsd",
        "netbsd",
        "openbsd",
        "dragonfly",
        "solaris",
        "windows",
        "android"
    }
    
    -- GLOBAL BUILD CONFIG SETTINGS --
    filter "configurations:Debug"
        flags { "Symbols" }

    filter {}
    
    -- GLOBAL PLATFORM INDEPENDENT DEFINES --
    
    -- default global cpu types.  can be overridden by platform architecture
    defines {"OBJTYPE='\"386\"'"}
    architecture "x86_64"
    
    -- GLOBAL SOURCE AND TARGET OBJECT LOCATIONS --
    objdir("src/build/obj")
    libdirs("luajit/src")  -- the luajit libraries
    libdirs("libuv/.libs")       -- the libuv libraries
    libdirs("src/build")       -- location of the statics that we build
    targetdir("src/build")

    -- GLOBAL INCLUDE SOURCES --
    includedirs { 
        "libuv/src",
        "libuv/include",
        "luajit/src",
        "src/styx/hosting/libuv/include",
        "src/styx/include",
        "fs/module"
        }

    -- GLOBAL LINK STAGE --
    --linkoptions { "-lm", "-v"}

    -- GLOBAL PLATFORM SPECIFIC SETTINGS --      
      
    -- TARGET BUILDS
    -- plat-specific include dirs might not be needed
    filter "platforms:linux" 
        defines {"SYSTARG=Linux"}
        system "linux"
        includedirs { "src/styx/platform/Linux/include" }

    filter { "platforms:windows" }
        defines { "SYSTARG=Nt" }
        system "windows"  -- does this assume VS?
        includedirs { "src/styx/platform/Nt/include" }

    filter { "platforms:freebsd" }
        defines { "SYSTARG=FreeBSD" }
        system "bsd" -- does this work for clang vs gcc targets chains?
        includedirs { "src/styx/platform/FreeBSD/include" }
    
    filter { "platforms:netbsd" }
        defines { "SYSTARG=NetBSD" }
        system "bsd" -- does this work for clang vs gcc targets chains?
        includedirs { "src/styx/platform/NetBSD/include" }
        
    filter { "platforms:openbsd" }
        defines { "SYSTARG=OpenBSD" }
        system "bsd" -- does this work for clang vs gcc targets chains?
        includedirs { "src/styx/platform/OpenBSD/include" }
        
    filter  { "platforms:dragonfly" }
        defines { "SYSTARG=DragonFly" }
        system "bsd" -- does this work for clang vs gcc targets chains?
        includedirs { "src/styx/platform/Dragonfly/include" }
        
    filter "platforms:macosx"
        defines { "SYSTARG=MacOSX"}
        system "macosx"
        --buildoptions {"-Wno-deprecated-declarations", "-Wuninitialized", "-Wunused", "-Wreturn-type",
        --    "-Wimplicit", "-Wno-four-char-constants", "-Wno-unknown-pragmas", "-pipe",
        --    "-fno-strict-aliasing", "-no-cpp-precomp"}
        includedirs { "src/styx/platform/MacOSX/include" }


    -- reset filtering --
    filter {}
    
    -- PROJECTS --
    
    -- inferno libs --
    include "src/styx/libs/lib9"        -- protocol/conversion/formatting
    include "src/styx/libs/libbio"      -- low-level i/o and rune support
    include "src/styx/libs/libsec"      -- crypto support
        
    -- utilities --
    include "src/styx/utils"

    -- the node9 kernel --
    include "src"


