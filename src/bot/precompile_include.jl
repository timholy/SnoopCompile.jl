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
    new_includer_file(package_name::String, package_path::String, os::Union{Vector{String}, Nothing})

Creates a "precompile_includer.jl" file.
"""
function new_includer_file(package_name::String, package_path::String, os::Union{Vector{String}, Nothing})
    includer_file = joinpath(dirname(package_path), "precompile_includer.jl")

    if isnothing(os)
        multiosstr = ""
    else
        multiosstr = ""
        for eachos in os
            multiosstr = multiosstr * """elseif Sys.is$eachos
            include("../deps/SnoopCompile/precompile/$eachos/precompile_$package_name.jl")
            """
        end
    end

    @info "$includer_file file will be created/overwritten"
    enclusure = """
    # precompile_enclusre (don't edit the following!)
    should_precompile = true
    ismultios = false
    @static if should_precompile
        @static if !ismultios
            include("../deps/SnoopCompile/precompile/precompile_$package_name.jl")
        $multiosstr
        end
    end # precompile_enclusure
    _precompile_()
    """
    Base.write(includer_file, enclusure)
end
################################################################
"""
    add_includer(package_path::String)

Writes the `include(precompile_includer.jl)` to the package file.
"""
function add_includer(package_path::String)
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
