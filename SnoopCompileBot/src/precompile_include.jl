"""
    new_includer_file(
        package_name::AbstractString,
        package_path:: AbstractString,
        precompiles_rootpath::AbstractString,
        os::Union{Vector{String}, Nothing},
        else_os::Union{String, Nothing},
        version::Union{Vector{VersionNumber}, Nothing},
        else_version::Union{VersionNumber, Nothing})

Creates a "precompile_includer.jl" file.

`package_path = pathof_noload(package_name)`
`precompiles_rootpath`: where the precompile files are stored.

# # Examples
```julia
SnoopCompile.new_includer_file("MatLang", "./src/MatLang.jl", "./deps/SnoopCompile/precompile", ["windows", "linux"], "linux", [v"1.0", v"1.4"], v"1.4")
```
"""
function new_includer_file(
    package_name::AbstractString,
    package_path:: AbstractString,
    precompiles_rootpath_in::AbstractString,
    os::Union{Vector{String}, Nothing},
    else_os::Union{String, Nothing},
    version::Union{Vector{VersionNumber}, Nothing},
    else_version::Union{VersionNumber, Nothing})

    # make the precompile path relative to src folder
    # this is the only path that is written to the disk by the bot, and it should be relative to make it generic.
    precompiles_rootpath = GoodPath(relpath(precompiles_rootpath_in, dirname(package_path)))

    os = standardize_osname(os)
    else_os = standardize_osname(else_os)

    # find multistr, ismultiversion, ismultios
    if isnothing(os)
        ismultios = false
        multistr = ""
        if isnothing(version)
            ismultiversion = false
            multiversionstr = ""
        else
            ismultiversion = true
            multiversionstr = _multiversion(package_name, precompiles_rootpath, version, else_version)
            multistr = multiversionstr
        end #if nothing vesion
    else
        ismultios = true
        if isnothing(version)
            ismultiversion = false
            multistr = _multios(package_name, precompiles_rootpath, os, else_os, ismultiversion)
        else
            ismultiversion = true
            multistr = _multios(package_name, precompiles_rootpath, os, else_os, ismultiversion, version, else_version)
        end # if nothing version
    end # if nothing os

    precompile_config = """
    should_precompile = true


    # Don't edit the following! Instead change the script for `snoop_bot`.
    ismultios = $ismultios
    ismultiversion = $ismultiversion
    # precompile_enclosure
    @static if !should_precompile
        # nothing
    elseif !ismultios && !ismultiversion
        include("$precompiles_rootpath/precompile_$package_name.jl")
        _precompile_()
    else
        $multistr
    end # precompile_enclosure
    """

    includer_file = "$(dirname(package_path))/precompile_includer.jl"
    @info "$includer_file file will be created/overwritten"
    Base.write(includer_file, precompile_config)
end

"""
Helper function for multios code generation
"""
function _multios(package_name, precompiles_rootpath, os_in, else_os, ismultiversion, version = nothing, else_version = nothing)
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
            multiversionstr = _multiversion(package_name, precompiles_rootpath, version, else_version, eachos)
            multistr = multistr * """
                $multiversionstr
            """
        else
            multistr = multistr * """
                include("$precompiles_rootpath/$eachos/precompile_$package_name.jl")
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
Helper function for multi Julia version code generation
"""
function _multiversion(package_name, precompiles_rootpath, version_in, else_version, eachos = "")
    version = similar(version_in, Any)
    version[:] = version_in[:]

    sort!(version)

    push!(version, else_version)

    version_length = length(version)
    multiversionstr = ""
    for (iversion, eachversion) in enumerate(version)

        if iversion == 1
            lowerbound = VersionNumber(eachversion.major, eachversion.minor, 0, ("DEV",))
            higherbound = VersionNumber(eachversion.major, eachversion.minor, 9)
            version_phrase = "@static if v\"$lowerbound\" <= VERSION <= v\"$higherbound\""
        elseif iversion == version_length
            version_phrase = "else"
        else
            lowerbound = VersionNumber(eachversion.major, eachversion.minor, 0, ("DEV",))
            higherbound = VersionNumber(eachversion.major, eachversion.minor, 9)
            version_phrase = "elseif v\"$lowerbound\" <= VERSION <= v\"$higherbound\""
        end
        multiversionstr = multiversionstr * "$version_phrase \n"

        if  iversion == version_length && isnothing(else_version)
            continue
        end

        multiversionstr = multiversionstr * """
            include("$precompiles_rootpath/$eachos/$(VersionFloat(eachversion))/precompile_$package_name.jl")
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

`package_path = pathof_noload(package_name)`
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
            @warn """removing SnoopCompile < v"1.2.2" code"""  # For backward compatibility
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
            if any(occursin.([r"end(\s)*#(\s)*module", "end"], Ref(package_lines[iLine])))
                endline = iLine
                break
            end
        end

        # add line or error
        try
            code = """
            include("precompile_includer.jl")
            """
            insert!(package_lines,endline,code) # add new empty line before the end
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

        if !occursin("include(\"precompile_includer.jl\")", Base.read(package_path, String))
            # TODO should we error here?
            @warn """SnoopCompileBot failed to add `"include(\"precompile_includer.jl\")"` to $package_path. You should do that manually!"""
        end
    end
end
