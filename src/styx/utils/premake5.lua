-- build support utils
project "ndate"
    kind "ConsoleApp"
    targetdir(".")
    files {"ndate.c"}
    links {"9"} 
