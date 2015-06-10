-- premake file for node9

-- hack for clang instead of gcc --
premake.gcc.cc  = 'clang'
premake.gcc.cxx = 'clang++'
--premake.gcc.ar = 'llvm-ar'
premake.gcc.as = 'llvm-as'

solution "node9-hosted"
    language "C"
    premake.gcc.cc  = 'clang'
    premake.gcc.cxx = 'clang++'
    
    
    -- GLOBAL BUILD DEFINES
    -- (in the actual install WORKING_DIR will need to become a runtime eval env var)
    defines { "ROOT='\"" .. _WORKING_DIR .. "/fs\"'", "SYSHOST=MacOSX", "SYSTARG=MacOSX", "OBJTYPE='\"386\"'" }
    
    -- PRODUCTION / TEST BUILD OPTIONS
    configurations { "Debug", "Release" }
    configuration "Debug"
        flags { "Symbols" }
    buildoptions {"-Wno-deprecated-declarations", "-Wuninitialized", "-Wunused", "-Wreturn-type", "-Wimplicit", "-Wno-four-char-constants",                 "-Wno-unknown-pragmas", "-pipe", "-fno-strict-aliasing", "-no-cpp-precomp"}
    linkoptions { "-lm", "-v"}

    -- EXTENDED PLATFORM SUPPORT and CROSS-BUILD OPTIONS
    --platforms {"native","x64","universal"}

    -- SOURCE AND TARGET OBJECT LOCATIONS
    objdir(_WORKING_DIR .. "/src/build/obj")
    libdirs(_WORKING_DIR .. "/luajit/src")  -- the luajit libraries
    libdirs(_WORKING_DIR .. "/libuv/.libs")       -- the libuv libraries
    libdirs(_WORKING_DIR .. "/src/build")       -- location of the statics that we build
    targetdir(_WORKING_DIR .. "/src/build")

    -- GLOBAL INCLUDE SOURCES --
    includedirs { 
        "libuv/include",
        --"src/styx/platform/MacOSX/include",
        "src/styx/hosting/libuv/include",
        "src/styx/include",
        "fs/module"}
    
    -- SUPPORT LIBRARY PROJECTS
    include "src/styx/libs/lib9"        -- protocol/conversion/formatting
    include "src/styx/libs/libbio"      -- low-level i/o and rune support
    include "src/styx/libs/libsec/port" -- crypto support
        
    -- UTILITY PROJECTS
    include "src/styx/utils"

    -- THE NODE9 KERNEL PROJECT
    include "src"
