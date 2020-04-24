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

`package_path = pathof_noload(package_name)`

# # Examples
```julia
SnoopCompile.new_includer_file("MatLang", joinpath(pwd(),"src/MatLang.jl"), ["windows", "linux"], "linux", [v"1.0", v"1.4"], v"1.4")
```
"""
function new_includer_file(
    package_name::AbstractString,
    package_path::AbstractString,
    os::Union{Vector{String}, Nothing},
    else_os::Union{String, Nothing},
    version::Union{Vector{VersionNumber}, Nothing},
    else_version::Union{VersionNumber, Nothing})

    ## Standardize different names from Github actions, Travis, etc
    # https://help.github.com/en/actions/reference/virtual-environments-for-github-hosted-runners#supported-runners-and-hardware-resources
    if !isnothing(os)
        os[occursin.("macos", os)] .= "apple"
        os[occursin.("osx", os)] .= "apple"
        os[occursin.("apple", os)] .= "apple"
        os[occursin.("ubuntu", os)] .= "linux"
        os[occursin.("linux", os)] .= "linux"
        os[occursin.("windows", os)] .= "windows"
    end
    if !isnothing(else_os)
        occursin.("macos", else_os) ? else_os = "apple" : nothing
        occursin.("osx", else_os) ? else_os = "apple" : nothing
        occursin.("apple", else_os) ? else_os = "apple" : nothing
        occursin.("ubuntu", else_os) ? else_os = "linux" : nothing
        occursin.("linux", else_os) ? else_os = "linux" : nothing
        occursin.("windows", else_os) ? else_os = "windows" : nothing
    end

    # find multistr, ismultiversion, ismultios
    if isnothing(os)
        ismultios = false
        multistr = ""
        if isnothing(version)
            ismultiversion = false
            multiversionstr = ""
        else
            ismultiversion = true
            multiversionstr = _multiversion(version, else_version, package_name)
            multistr = multiversionstr
        end #if nothing vesion
    else
        ismultios = true
        if isnothing(version)
            ismultiversion = false
            multistr = _multios(os, else_os, package_name, ismultiversion)
        else
            ismultiversion = true
            multistr = _multios(os, else_os, package_name, ismultiversion, version, else_version)
        end # if nothing version
    end # if nothing os

    precompile_config = """
    should_precompile = true


    # Don't edit the following! Instead change the script for @snoopi_bot.
    ismultios = $ismultios
    ismultiversion = $ismultiversion
    # precompile_enclosure
    @static if !should_precompile
        # nothing
    elseif !ismultios && !ismultiversion
        include("../deps/SnoopCompile/precompile/precompile_$package_name.jl")
        _precompile_()
    else
        $multistr
    end # precompile_enclosure
    """

    includer_file = joinpath(dirname(package_path), "precompile_includer.jl")
    @info "$includer_file file will be created/overwritten"
    Base.write(includer_file, precompile_config)
end

"""
Helper function for multios code generation
"""
function _multios(os_in, else_os, package_name, ismultiversion, version = nothing, else_version = nothing)
    os = similar(os_in, Any)
    os[:] = os_in[:]

    push!(os, string(else_os))

    os_length = length(os)
    multistr = ""
    for (iOs, eachos) in enumerate(os)

        if iOs == 1
            os_phrase = "@static if Sys.is$eachos()"
        elseif iOs == os_length
            os_phrase = "else"
        else
            os_phrase = "elseif Sys.is$eachos()"
        end
        multistr = multistr * "$os_phrase \n"

        if iOs == os_length && isnothing(else_os)
            continue
        end

        if ismultiversion
            multiversionstr = _multiversion(version, else_version, package_name, eachos)
            multistr = multistr * """
                $multiversionstr
            """
        else
            multistr = multistr * """
                include("../deps/SnoopCompile/precompile/$eachos/precompile_$package_name.jl")
                _precompile_()
            """
        end
    end # for os

    multistr = multistr * """
        end
    """
    return multistr
end


"""
Helper function for multiversion code generation
"""
function _multiversion(version_in, else_version, package_name, eachos = "")
    version = similar(version_in, Any)
    version[:] = version_in[:]

    sort!(version)

    push!(version, else_version)

    version_length = length(version)
    multiversionstr = ""
    for (iVersion, eachversion) in enumerate(version)

        if iVersion == 1
            version_phrase = "@static if VERSION <= v\"$eachversion\""
        elseif iVersion == version_length
            version_phrase = "else"
        else
            version_phrase = "elseif VERSION <= v\"$eachversion\""
        end
        multiversionstr = multiversionstr * "$version_phrase \n"

        if  iVersion == version_length && isnothing(else_version)
            continue
        end

        multiversionstr = multiversionstr * """
            include("../deps/SnoopCompile/precompile/$eachos/$eachversion/precompile_$package_name.jl")
            _precompile_()
        """
    end # for version

    multiversionstr = multiversionstr * """
        end
    """
    return multiversionstr
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
