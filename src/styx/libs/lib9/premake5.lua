
project "lib9"
    -- is this kind of app
    kind "StaticLib"
    targetname "9"
    buildoptions {"-fPIC"}
    -- is dependent on these files
    files {"convD2M.c", "convM2D.c", "convM2S.c", "convS2M.c", "fcallfmt.c", "runestrchr.c", "runestrlen.c", "runetype.c", "strtoll.c", "strtoull.c",
        "rune.c", "argv0.c", "charstod.c", "cistrcmp.c", "cistrncmp.c", "cistrstr.c", "cleanname.c", "create.c", "dirwstat.c", "dofmt.c", "dorfmt.c",
        "errfmt.c", "exits.c", "fmt.c", "fmtfd.c", "fmtlock.c", "fmtprint.c", "fmtquote.c", "fmtrune.c", "fmtstr.c", "fmtvprint.c", "fprint.c",
        "getfields.c", "nulldir.c", "pow10.c", "print.c", "qsort.c", "readn.c", "rerrstr.c", "runeseprint.c", "runesmprint.c", "runesnprint.c",
        "runevseprint.c", "seek.c", "seprint.c", "smprint.c", "snprint.c", "sprint.c", "strdup.c", "strecpy.c", "sysfatal.c", "tokenize.c", "u16.c",
        "u32.c", "u64.c", "utflen.c", "utfnlen.c", "utfrrune.c", "utfrune.c", "utfecpy.c", "vfprint.c", "vseprint.c", "vsmprint.c", "vsnprint.c",
        "dirstat-posix.c", "errstr-posix.c", "getuser-posix.c", "getwd-posix.c", "sbrk-posix.c", "isnan-posix.c" }
