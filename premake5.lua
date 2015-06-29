-- premake file for node9
--
-- platform specific settings include
-- 
--   o the compiler / build chain
--   o the defines
--   o the build options
--   o the includes
--   o the libraries
--   

-- GLOBAL SOLUTION SETTINGS --

solution "node9-hosted"

    language "C"

    configurations { "Debug", "Release" }
    
    -- GLOBAL BUILD CONFIG SETTINGS --
    configuration "Debug"
        flags { "Symbols" }

    -- GLOBAL PLATFORM INDEPENDENT DEFINES --
    -- (replace with a platform independent getenv call)
    --defines { "ROOT='\"" .. _WORKING_DIR .. "/fs\"'" }

    -- GLOBAL SOURCE AND TARGET OBJECT LOCATIONS --
    -- (probably dont need explicit WORKING_DIR on these) 
    objdir(_WORKING_DIR .. "/src/build/obj")
    libdirs(_WORKING_DIR .. "/luajit/src")  -- the luajit libraries
    libdirs(_WORKING_DIR .. "/libuv/.libs")       -- the libuv libraries
    libdirs(_WORKING_DIR .. "/src/build")       -- location of the statics that we build
    targetdir(_WORKING_DIR .. "/src/build")

    -- GLOBAL INCLUDE SOURCES --
    includedirs { 
	"libuv/src",
        "libuv/include",
        "src/styx/hosting/libuv/include",
        "src/styx/include",
        "fs/module"
        }

    -- GLOBAL LINK STAGE --
    linkoptions { "-lm", "-v"}


    -- GLOBAL PLATFORM SPECIFIC SETTINGS --
    filter "system:macosx"
        defines { "SYSHOST=MacOSX", "SYSTARG=MacOSX", "OBJTYPE='\"386\"'" }
    
        buildoptions {"-Wno-deprecated-declarations", "-Wuninitialized", "-Wunused", "-Wreturn-type",
            "-Wimplicit", "-Wno-four-char-constants", "-Wno-unknown-pragmas", "-pipe",
            "-fno-strict-aliasing", "-no-cpp-precomp"}

        includedirs { "src/styx/platform/MacOSX/include" }

    filter "system:linux" 
        defines { "SYSHOST=Linux", "SYSTARG=Linux", "OBJTYPE='\"386\"'" }
        includedirs { "src/styx/platform/Linux/include" }

    --filter { "system:bsd" }
    --    defines { "SYSHOST=NetBSD", "SYSTARG=NetBSD", "OBJTYPE='\"386\"'" }
    
    --filter { "system:windows" }
    --    defines { "SYSHOST=Nt", "SYSTARG=Nt", "OBJTYPE='\"386\"'" }
   

    -- reset filtering --
    filter {}
    
    -- PROJECTS --
    
    -- inferno libs --
    include "src/styx/libs/lib9"        -- protocol/conversion/formatting
    include "src/styx/libs/libbio"      -- low-level i/o and rune support
    include "src/styx/libs/libsec/port" -- crypto support
        
    -- utilities --
    include "src/styx/utils"

    -- the node9 kernel --
    include "src"
