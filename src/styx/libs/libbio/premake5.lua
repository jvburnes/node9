project "libbio"
    -- is this kind of app
    kind "StaticLib"
    targetname "bio"
    buildoptions { "-fPIC" }
    -- warnings and config settings
    -- and is dependent on these files
    files {"bbuffered.c", "bfildes.c", "bflush.c", "bgetrune.c", "bgetc.c", "bgetd.c", "binit.c", "boffset.c", "bprint.c", "bputrune.c", "bputc.c",             "brdline.c", "brdstr.c", "bread.c", "bseek.c", "bvprint.c", "bwrite.c"}
