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
    new_includer_file(
        package_name::AbstractString,
        package_path::AbstractString,
        os::Union{Vector{String}, Nothing},
        else_os::Union{String, Nothing},
        version::Union{Vector{VersionNumber}, Nothing},
        else_version::Union{VersionNumber, Nothing})

Creates a "precompile_includer.jl" file.

`package_path` should be the full path to the defining file for the package, i.e., identical to `pathof(ThePkg)`. However, `pathof(module)` isn't used to prevent the need to load the package.
"""
function new_includer_file(
    package_name::AbstractString,
    package_path::AbstractString,
    os::Union{Vector{String}, Nothing},
    else_os::Union{String, Nothing},
    version::Union{Vector{VersionNumber}, Nothing},
    else_version::Union{VersionNumber, Nothing})

    includer_file = joinpath(dirname(package_path), "precompile_includer.jl")

    if isnothing(os)
        ismultios = false

        if isnothing(version)
            ismultiversion = false
            multiversionstr = ""

        else
            ismultiversion = true
            version_length = length(version)
            multiversionstr = """@static if VERSION <= $(version[1])
                include("../deps/SnoopCompile/precompile/$(version[1])/precompile_$package_name.jl")
                _precompile_()
            """
            if length(version) > 1
                for (iVersion, eachversion) in enumerate(version[2:end])
                    if iVersion == version_length
                        if isnothing(else_version)
                            version_elsephrase = "elseif VERSION <= $eachversion"
                        else
                            version_elsephrase = "else"
                            eachversion = "else_version"
                        end
                    else
                        version_elsephrase = "elseif VERSION <= $eachversion"
                    end
                multiversionstr = multiversionstr * """$version_elsephrase
                    include("../deps/SnoopCompile/precompile/$eachversion/precompile_$package_name.jl")
                    _precompile_()
                """
                end # for version
            end # if length versoin

        end #if nothing vesion

        multistr = """$multiversionstr
            end
        """

    else
        ismultios = true
        os_length = length(os)
        if isnothing(version)
            ismultiversion = false
            multistr = """@static if Sys.is$(os[1])()
                include("../deps/SnoopCompile/precompile/$(os[1])/precompile_$package_name.jl")
                _precompile_()
            """
            if length(os) > 1
                for (iOs, eachos) in enumerate(os[2:end])
                    if iOs == os_length
                        if isnothing(else_os)
                            os_elsephrase = "elseif Sys.is$eachos()"
                        else
                            os_elsephrase = "else"
                            eachos = "else_os"
                        end
                    else
                        os_elsephrase = "elseif Sys.is$eachos()"
                    end
                    multistr = multistr * """$os_elsephrase
                        include("../deps/SnoopCompile/precompile/$eachos/precompile_$package_name.jl")
                        _precompile_()
                    """
                end # for os
            end # if length os
        else
            ismultiversion = true
            multistr = """@static if Sys.is$(os[1])()
                include("../deps/SnoopCompile/precompile/$(os[1])/precompile_$package_name.jl")
                _precompile_()
            """
            if length(os) > 1
                for (iOs, eachos) in enumerate(os[2:end])

                    if iOs == os_length
                        if isnothing(else_os)
                            os_elsephrase = "elseif Sys.is$eachos()"
                        else
                            os_elsephrase = "else"
                            eachos = "else_os"
                        end
                    else
                        os_elsephrase = "elseif Sys.is$eachos()"
                    end

                    multiversionstr = """@static if VERSION <= $(version[1])
                        include("../deps/SnoopCompile/precompile/$eachos/$(version[1])/precompile_$package_name.jl")
                        _precompile_()
                    """
                    if length(version) > 1
                        for (iVersion, eachversion) in enumerate(version[2:end])

                            if iVersion == version_length
                                if isnothing(else_version)
                                    version_elsephrase = "elseif VERSION <= $eachversion"
                                else
                                    version_elsephrase = "else"
                                    eachversion = "else_version"
                                end
                            else
                                version_elsephrase = "elseif VERSION <= $eachversion"
                            end

                            multiversionstr = multiversionstr * """$version_elsephrase
                            include("../deps/SnoopCompile/precompile/$eachos/$eachversion/precompile_$package_name.jl")
                            _precompile_()
                            """
                        end # for version
                    end # if length version

                    multiversionstr = multiversionstr *"""
                        end
                    """

                    multistr = multistr * """$os_elsephrase
                        $multiversionstr
                    """
                end # for os
            end #if length os

        end # if nothing version

        multistr = multistr * """
            end
        """
    end # if nothing os

    @info "$includer_file file will be created/overwritten"
    enclosure = """
    # precompile_enclusre
    should_precompile = true
    ismultios = $ismultios
    ismultiversion = $ismultiversion
    # Don't edit the following!
    @static if !should_precompile
            # nothing
    elseif !ismultios && !ismultiversion
        include("../deps/SnoopCompile/precompile/precompile_$package_name.jl")
        _precompile_()
    else
        $multistr
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
        for iLine = endline:-1:1
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
