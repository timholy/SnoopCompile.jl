export BotConfig, snoop_bot, snoop_bench, snoopi_bot, snoopc_bot, snoopi_bench, snoopv_bench

if VERSION <=  v"1.1"
    isnothing(x) = x == nothing
end
if VERSION <=  v"1.2"
    Base.print(io, ::Nothing) = Base.print(io, "")
    Base.print(::Base.GenericIOBuffer{Array{UInt8,1}}, ::Nothing) = Base.print(io, "")
    Base.string(::Nothing) = ""
end
################################################################
const UStrings = Union{AbstractString,Regex,AbstractChar}

"""
    BotConfig(package_name ; blacklist, os, else_os, version, else_version, package_path, precompiles_rootpath, subst, tmin)

Construct a SnoopCompile bot configuration. `package_name` is the name of the package. This object is fed to the `snoopi_bot`.

# Arguments:
- `package_name::AbstractString`

You may supply the following optional **keyword** arguments:

- `blacklist` : A vector of of Strings (or RegExp) to remove some precompile sentences

- `exhaustive`: passing `true` enables exhaustive testing of each precompilation signature, however, it slows down the processing stage. Defaults to `false`. Use this feature if SnoopCompile benchmark or your CI fails. This feature also prints the errors, which can help to find the `blacklist`s indivudally and disble `exhaustive` for the next runs.

- `os`: A vector of of Strings (or RegExp) to give the list of os that you want to generate precompile signatures for. Each element will call a `Sys.is\$eachos()` function.

Example: `os = ["windows", "linux"]`

- `else_os`: If you want to use a specific os for any other os, give `else_os` the name of that os. If you don't want to precompile for other os pass nothing.

Example: `else_os = "linux"`

- `version`: A vector of of versions to give the list of versions that you want to generate precompile signatures for.

Example: `version = [v"1.1", v"1.4.1", "nightly"]`

It is assumed that the generated precompile signatures are valid for patch versions of Julia (e.g. giving v"1.4.2" assumses v"1.4.0" to v"1.4.9").

- `else_vresion`: If you want to use a specific version for any other version, give `else_version` the name of that version.

Example: `else_version = v"1.4.1"`

- `package_path`: path to the main `.jl` file of the package (similar to `pathof`). Default path is `pathof_noload(package_name)`.

- `precompiles_rootpath`: the path where precompile files are stored. Default path is "\$(dirname(dirname(package_path)))/deps/SnoopCompile/precompile".

- `subst` : A vector of pairs of Strings (or RegExp) to replace a packages precompile setences with another's package like `["ImageTest" => "Images"]`.

- `tmin`: Methods that take less time than `tmin` will not be reported. Defaults to 0.0.

# Example
```julia
# A full example:
BotConfig("MatLang", blacklist = ["badfunction"], os = ["linux", "windows", "macos"], else_os = "linux", version = ["1.4.1", "1.2", "1.0.5"], else_version = "1.4.1" )

# Different examples for other possibilities:
BotConfig("MatLang")

BotConfig("MatLang", blacklist = ["badfunction"])

BotConfig("MatLang", os = ["linux", "windows"])

BotConfig("MatLang", os = ["windows", "linux"], else_os = "linux")

BotConfig("MatLang", version = [v"1.1", v"1.4.1"])

BotConfig("MatLang", version = [v"1.1", v"1.4.1"], else_version = v"1.4.1")

BotConfig("MatLang", os = ["linux", "windows"], version = [v"1.1", v"1.4.1"])

# etc
```
"""
struct BotConfig
    package_name::AbstractString
    blacklist::Vector{UStrings}
    exhaustive::Bool
    os::Union{Vector{String}, Nothing}
    else_os::Union{String, Nothing}
    version::Union{Vector{VersionNumber}, Nothing}
    else_version::Union{VersionNumber, Nothing}
    package_path::AbstractString
    precompiles_rootpath::AbstractString
    subst::Vector{Pair{UStrings, UStrings}}
    tmin::AbstractFloat
end

function BotConfig(
    package_name::AbstractString;
    blacklist::AbstractVector = String[],
    exhaustive::Bool = false,
    os::Union{Vector{String}, Nothing} = nothing,
    else_os::Union{String, Nothing} = nothing,
    version::Union{Vector{<:Union{VersionNumber,String}}, Nothing} = nothing,
    else_version::Union{VersionNumber, String, Nothing} = nothing,
    package_path::AbstractString = pathof_noload(package_name),
    precompiles_rootpath::AbstractString = "$(dirname(dirname(package_path)))/deps/SnoopCompile/precompile",
    subst::AbstractVector = Vector{Pair{UStrings, UStrings}}(),
    tmin::AbstractFloat = 0.0,
    )
    
    if !isnothing(version)
        version = JuliaVersionNumber.(version)
    end
    if !isnothing(else_version)
        else_version = JuliaVersionNumber(else_version)
    end

    return BotConfig(package_name, blacklist, exhaustive, os, else_os, version, else_version, GoodPath(package_path), GoodPath(precompiles_rootpath), subst, tmin)
end

include("bot/botutils.jl")
include("bot/precompile_include.jl")
include("bot/precompile_activation.jl")
include("bot/snoop_bot.jl")
include("bot/snoop_bench.jl")
include("bot/deprecations.jl")
