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
    os = ""
    osfun = allos_funs[1] # temp
    for osfun in allos_funs
        if osfun()
            os = string(osfun)[3:end]
            break
        end
    end
    if os == ""
        @error "os is not detected"
    end
    return os, osfun
end
################################################################
"""
    new_includer_file(package_name::AbstractString, package_path::AbstractString, os::Union{Vector{String}, Nothing})

Creates a "precompile_includer.jl" file.

`package_path` should be the full path to the defining file for the package, i.e., identical to `pathof(ThePkg)`. However, `pathof(module)` isn't used to prevent the need to load the package.
"""
function new_includer_file(package_name::AbstractString, package_path::AbstractString, os::Union{Vector{String}, Nothing})
    includer_file = joinpath(dirname(package_path), "precompile_includer.jl")

    if isnothing(os)
        multiosstr = ""
        ismultios = false
    else
        multiosstr = ""
        for eachos in os
            multiosstr = multiosstr * """elseif Sys.is$eachos()
                include("../deps/SnoopCompile/precompile/$eachos/precompile_$package_name.jl")
                _precompile_()
            """
        end
        ismultios = true
    end

    @info "$includer_file file will be created/overwritten"
    enclosure = """
    # precompile_enclusre
    should_precompile = true
    ismultios = $ismultios
    # Don't edit the following!
    @static if !should_precompile
            # nothing
    elseif !ismultios
        include("../deps/SnoopCompile/precompile/precompile_$package_name.jl")
        _precompile_()
    $multiosstr
    end # precompile_enclosure
    """
    Base.write(includer_file, enclosure)
end
################################################################
"""
    add_includer(package_name::AbstractString, package_path::AbstractString)

Writes the `include(precompile_includer.jl)` to the package file.

`package_path` should be the full path to the defining file for the package, i.e., identical to `pathof(ThePkg)`. However, `pathof(module)` isn't used to prevent the need to load the package.
"""
function add_includer(package_name::AbstractString, package_path::AbstractString)
    if !isfile(package_path)
        error("$package_path file doesn't exist")
    end

    # read package
    package_text = Base.read(package_path, String)

    # Checks if any other precompile code already exists (only finds explicitly written _precompile_)
    if occursin("_precompile_()",package_text)
        if occursin("""include("../deps/SnoopCompile/precompile/precompile_$package_name.jl")""", package_text)
            # removing SnoopCompile < v"1.2.2" code
            replace(package_text, "_precompile_()"=>"")
            replace(package_text, """include("../deps/SnoopCompile/precompile/precompile_$package_name.jl")"""=>"")
        else
            error("""Please remove `_precompile_()` and any other code that includes a `_precompile_()` function from $package_path
            SnoopCompile automatically creates the code.
            """)
        end
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
            include("precompile_includer.jl")
            """
            insert!(package_lines,endline-1,code) # add new empty line before the end
        catch e
            @error("Error occured during writing", e)
            return nothing
        end

        # write the lines
        if package_lines != nothing
            open(package_path, "w") do io
                for l in package_lines
                    Base.write(io, l)
                end
            end
        end
    end
end
