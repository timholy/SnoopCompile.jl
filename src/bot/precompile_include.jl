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
################################################################
"""
    precompile_pather(package_name::String)

To get the path of precompile_package_name.jl file

Written exclusively for SnoopCompile Github actions.
# Examples
```julia
precompile_path, precompileFolder = precompile_pather("MatLang")
```
"""
function precompile_pather(package_name::String, ismultios::Bool)
    if !ismultios
        return "\"../deps/SnoopCompile/precompile/precompile_$package_name.jl\"",
        "$(pwd())/deps/SnoopCompile/precompile/"
    else
        os = detectos()
        return "\"../deps/SnoopCompile/precompile/$os/precompile_$package_name.jl\"",
        "$(pwd())/deps/SnoopCompile/precompile/$os"
    end
end

precompile_pather(package_name::Symbol, ismultios::Bool) = precompile_pather(string(package_name))
precompile_pather(package_name::Module, ismultios::Bool) = precompile_pather(string(package_name))
