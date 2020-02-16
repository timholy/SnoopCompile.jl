"""
    detectOS()

Returns Operating System of a machine as a string.
"""
function detectOS()
allos = [Sys.iswindows,
         Sys.isapple,
         Sys.islinux,
         Sys.isbsd,
         Sys.isdragonfly,
         Sys.isfreebsd,
         Sys.isnetbsd,
         Sys.isopenbsd,
         Sys.isjsvm]
    for os in allos
        if os()
            output = string(os)[3:end]
            break
        end
    end
    return output
end
