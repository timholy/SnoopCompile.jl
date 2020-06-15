################################################################
"""
    timesum(snoop::Vector{Tuple{Float64, Core.MethodInstance}}, unit = :s)

Calculates the total time measured by a snoop macro. `unit` can be :s or :ms.

# Examples
```julia
using SnoopCompile
data = @snoopi begin
    using MatLang
    MatLang_rootpath = dirname(dirname(pathof("MatLang")))

    include("\$MatLang_rootpath/test/runtests.jl")
end
println(timesum(data, :ms))
```
"""
function timesum(snoop::Vector{Tuple{Float64, Core.MethodInstance}}, unit::Symbol = :s)
    if isempty(snoop)
        t = 0.0
    else
        t = sum(first, snoop)
    end
    if unit == :s
        t = round(t, digits = 6)
    elseif unit == :ms
        t = round(t * 1000, digits = 3)
    else
        throw(ArgumentError("unit should be `:s` or `:ms`"))
    end
    return t
end
################################################################
"""
    os_string, os_func = detectOS()

Returns Operating System of a machine as a string and a function `os_func()` that will return
`true` on the current OS.

# Examples
```julia
julia> detectOS()
("windows", Base.Sys.iswindows)
```
"""
function detectOS()
allos_funs = [
         Sys.iswindows,
         Sys.isapple,
         Sys.islinux,
         Sys.isbsd]
    if VERSION >= v"1.1"
        allos_funs = [allos_funs...,
                  Sys.isdragonfly,
                  Sys.isfreebsd,
                  Sys.isnetbsd,
                  Sys.isopenbsd]
    end
    if VERSION >= v"1.2"
        push!(allos_funs, Sys.isjsvm)
    end

    os = ""
    osfun = allos_funs[1] # temp
    for osfun in allos_funs
        if osfun()
            os = split(string(osfun), '.')[end][3:end]
            return os, osfun
        end
    end
    @error "os is not detected"
end
################################################################
"""
    standardize_osname(input::String)
    standardize_osname(inputs::Vector{String})

Standardize different names from Github actions, Travis, etc

https://help.github.com/en/actions/reference/virtual-environments-for-github-hosted-runners#supported-runners-and-hardware-resources

# Examples
```jldoctest
julia> SnoopCompile.standardize_osname("ubuntu-latest")
"linux"

julia> SnoopCompile.standardize_osname(["ubuntu-latest", "macos-latest"])
2-element Array{String,1}:
 "linux"
 "apple"
```
"""
function standardize_osname(input::String)
    for (key, standard) in OS_MAP
        if occursin(key, input)
            input = standard
        end
    end
    return input
end
standardize_osname(inputs::Vector{String}) = standardize_osname.(inputs)
standardize_osname(input::Nothing) = input

const OS_MAP = Dict(
    "macos" => "apple",
    "mac" => "apple",
    "osx" => "apple",
    "apple" => "apple",
    "ubuntu" => "linux",
    "linux" => "linux",
    "win" => "windows",
    "windows" => "windows",
)
################################################################

using FilePathsBase

export GoodPath
# to convert WindowsPath before they get inside the SnoopCompile code
# GoodPath(inp::String) = inp |> Path |> _GoodPath |> string
# _GoodPath(path::WindowsPath) = PosixPath((path.drive, path.segments...))
# _GoodPath(path) = path
GoodPath(x::String) = replace(x, "\\" => "/") # doesn't remove / from the end of the strings
goodjoinpath(args...) = GoodPath(joinpath(args...))

################################################################
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

"""
search for the script! - needed because of confusing paths when referencing pattern_or_file in CI
"""
function searchdirsboth(rootpaths::Array{String}, pattern_or_file::AbstractString)
    if isfile(pattern_or_file)
        return pattern_or_file
    elseif isfile("../../$pattern_or_file") # if in deps/SnoopCompile
        return "../../$pattern_or_file"
    else
        found_files = searchdirs(rootpaths, pattern_or_file)
        if length(found_files) === 0
            found_files = searchdirsfile(rootpaths, pattern_or_file)
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
May launch a separate Julia process to find the package.

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

################################################################
"""
Get the float version from semver version
```
julia> VersionFloat(v"1.4.2")
"1.4"
```
"""
VersionFloat(v::VersionNumber) = join(split(string(v),'.')[1:2],'.')

# https://github.com/JuliaLang/julia/pull/36223:
"""
    JuliaVersionNumber(v::String)
    JuliaVersionNumber(v::VersionNumber)
returns the Julia version number by following the same specifications as VersionNumber.
`JuliaVersionNumber` will fetch the latest nightly version number if `"nightly"` or `"latest"` is given as the input.
# Examples
```julia
julia> JuliaVersionNumber("nightly")
v"1.6.0-DEV"
```
```jldoctest
julia> JuliaVersionNumber("1.2.3")
v"1.2.3"
julia> JuliaVersionNumber(v"1.2.3")
v"1.2.3"
```
"""
JuliaVersionNumber(v::VersionNumber) = v
function JuliaVersionNumber(v::String)
    if in(v, ["nightly", "latest"])
        version_path = download(
            "https://raw.githubusercontent.com/JuliaLang/julia/master/VERSION",
            joinpath(tempdir(), "VERSION.txt"),
        )
        version_str = replace(Base.read(version_path, String), "\n" => "")
        return VersionNumber(version_str)
    else
        return VersionNumber(v)
    end
end
