export GoodPath
# to convert WindowsPath before they get inside the SnoopCompile code
GoodPath(x::String) = replace(x, "\\" => "/")
goodjoinpath(args...) = GoodPath(joinpath(args...))

################################################################
using FilePathsBase
"""
     searchdir(rootpath::String, pattern::AbstractString)
a function to search a directory.
```julia
julia> searchdir("src", "/bot.jl")
1-element Array{String,1}:
 "src/bot.jl"
```
"""
function searchdir(rootpath::String, pattern::AbstractString)
    found_files = String[]
    for file in walkpath(Path(rootpath))
        if occursin(pattern, GoodPath(string(file)))
            push!(found_files, GoodPath(string(file)))
        end
    end
    return found_files
end

"""
Searches for the file rather a path.
"""
searchdirfile(rootpath::String, file::AbstractString) = searchdir(rootpath, string(Path(file).segments[end]))

"""
    searchdirs(rootpaths::Array{String}, pattern::AbstractString)

a function to search multiple directories.

```julia
julia> searchdirs(["./src", "./test"], "/bot.jl")
2-element Array{String,1}:
 "./src/bot.jl"
 "./test/bot/bot.jl"
```
"""
function searchdirs(rootpaths::Array{String}, pattern::AbstractString)
    unique(
        reduce(vcat,
            searchdir.(rootpaths, pattern)
        )
    )
end

"""
Searches for the file rather a path.
"""
searchdirsfile(rootpaths::Array{String}, file::AbstractString) = searchdirs(rootpaths, basename(file))

function searchdirsboth(rootpaths::Array{String}, pattern_or_file::AbstractString)
    if isfile(pattern_or_file)
        return pattern_or_file
    elseif isfile("../../$pattern_or_file") # if in deps/SnoopCompile
        return "../../$pattern_or_file"
    else
        found_files = searchdirs(rootpaths, pattern_or_file)
        if length(found_files) === 0
            found_files = searchdirsfiles(rootpaths, pattern_or_file)
            if length(found_files) === 0
                @error "Couldn't find $(pattern_or_file)"
            elseif length(found_files) > 1
                @error "Multiple $(pattern_or_file) exists at the current directory."
            else
                pattern_or_file = found_files[1]
            end
        elseif length(found_files) > 1
            @error "Multiple $(pattern_or_file) exists at the current directory."
        else
            pattern_or_file = found_files[1]
        end
    end
    return pattern_or_file
end
################################################################

export pathof_noload

"""
Returns a package's path without loading the package in the main Julia process.
# Examples
```julia
pathof_noload("MatLang")
```
"""
function pathof_noload(package_name::String)
    path = Base.find_package(package_name)
    if isnothing(path)
        cmd = "import $package_name; print(pathof($package_name))"
        try
            path = Base.read(`julia -e $cmd`, String)
            return GoodPath(path)
        catch
            try
                path = Base.read(`julia --project=@. -e $cmd`, String)
                return GoodPath(path)
            catch
                @error "Couldn't find the path of $package_name"
            end
        end
    else
        return GoodPath(path)
    end
end

################################################################

import Pkg
"""
Should be removed once Pkg allows adding test dependencies to the current environment

Used in Github Action workflow yaml file
"""
function addtestdep()

    if isfile("test/Test.toml")
        toml = Pkg.TOML.parsefile("test/Test.toml")
        test_deps = get(toml, "deps", nothing)
    elseif isfile("test/Project.toml")
        toml = Pkg.TOML.parsefile("test/Project.toml")
        test_deps = get(toml, "deps", nothing)
    else
        toml = Pkg.TOML.parsefile("Project.toml")
        test_deps = get(toml, "extras", nothing)
    end

    if !isnothing(test_deps)
        for (name, uuid) in test_deps
            Pkg.add(Pkg.PackageSpec(name = name, uuid = uuid))
        end
    end
end
