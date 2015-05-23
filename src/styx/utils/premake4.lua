-- build support utils
project "ndate"
    kind "ConsoleApp"
    targetdir(".")
    files {"ndate.c"}
    linkoptions {"-v"}
    links {"9"} 
