"""
    detectOS()

Returns Operating System of a machine as a string as the 1st output and the osfun as the 2nd output.
"""
function detectOS()
allos_funs = [
         Sys.iswindows,
         Sys.isapple,
         Sys.islinux,
         Sys.isbsd,
         Sys.isdragonfly,
         Sys.isfreebsd,
         Sys.isnetbsd,
         Sys.isopenbsd,
         Sys.isjsvm]
    for osfun in allos_funs
        if osfun()
            os = string(osfun)[3:end]
            break
        end
    end
    return os, osfun
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
        os = detectos()[1]
        return "\"../deps/SnoopCompile/precompile/$os/precompile_$package_name.jl\"",
        "$(pwd())/deps/SnoopCompile/precompile/$os"
    end
end

precompile_pather(package_name::Symbol, ismultios::Bool) = precompile_pather(string(package_name))
precompile_pather(package_name::Module, ismultios::Bool) = precompile_pather(string(package_name))
################################################################
"""
    create_includer_file(package_path::String, precompile_path::String)

Creates a "precompile_includer.jl" file if it doesn't exist.

create_includer_file(package_path, precompile_path)
"""
function create_includer_file(package_path::String, precompile_path::String)
    includer_file = joinpath(dirname(package_path), "precompile_includer.jl")
    if isfile(includer_file)
        @info "$includer_file already exists"
        return nothing
    else
        @info "$includer_file file will be created"
        enclusure = """
        # precompile_enclusre (don't edit the following!)
        should_precompile = true
        @static if should_precompile


        end # precompile_enclusure
        """
        Base.write(includer_file, enclusure)
    end
end
################################################################
"""
    add_includer(package_path::String, precompile_path::String)

Writes the `include(precompile_includer.jl)` to the package file.
"""
function add_includer(package_path::String, precompile_path::String)
    if !isfile(package_path)
        error("$package_path file doesn't exist")
    end

    # read package
    package_text = Base.read(package_path, String)

    # Checks if any other precompile code already exists
    if occursin("_precompile_()",package_text)
        error("""Please remove `_precompile_()` and any other code that includes a `_precompile_()` function from $package_path
        New version of SnoopCompile automatically creates the code.
        """)
    elseif occursin(r"#\s*include\(\"precompile_includer.jl\"\)", package_text)
        error("""Please uncomment `\"include(\"precompile_includer.jl\")\"`
        Set `should_precompile = false` instead for disabling precompilation.
        """)
    end

    # Adding include to source
    if occursin("include(\"precompile_includer.jl\")", package_text)
        # has precompile_includer
        @info "Package already has \"include(\"precompile_includer.jl\")\""
        return nothing
    else
        # no precompile_includer
        @info "SnoopCompile will try to write  \"include(\"precompile_includer.jl\")\" before end of the module in $package_path. Assume that the last `end` is the end of a module."

        # open lines
        package_lines = Base.open(package_path) do io
            Base.readlines(io, keep=true)
        end

        ## find end of a module
        # assumes that the last `end` is the end of a module
        endline = length(package_lines)
        for iLine = endline:1
            if any(occursin.(["end # module", "end"], Ref(package_lines[iLine])))
                endline = iLine
                break
            end
        end

        # add line or error
        try
            code = """
            "include("precompile_includer.jl")"
            """
            insert!(lines,iLine-1,code) # add new empty line before the end
        catch e
            @error("Error occured during writing", e)
            return nothing
        end

        # write the lines
        if lines != nothing
            open(package_path, "w") do io
                for l in lines
                    write(io, l)
                end
            end
        end
    end
end
