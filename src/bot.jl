export BotConfig, @snoopi_bot, @snoopi_bench

if VERSION <=  v"1.1"
    isnothing(x) = x == nothing
end
################################################################
const UStrings = Union{AbstractString,Regex,AbstractChar}

"""
    BotConfig

Config object that holds the options and configuration for the SnoopCompile bot. This object is fed to the `@snoopi_bot`.

# Arguments:
- `package_name::AbstractString`

## optional:

- `subst` : A vector of pairs of Strings (or RegExp) to replace a packages precompile setences with another's package like `["ImageTest" => "Images"]`.

- `blacklist` : A vector of of Strings (or RegExp) to remove some precompile sentences

- `os`: A vector of of Strings (or RegExp) to give the list of os that you want to generate precompile signatures for. Each element will call a `Sys.is\$eachos()` function.


# Example
```julia
BotConfig("MatLang", blacklist = ["badfunction"], os = ["linux", "windows"])
```
"""
struct BotConfig
    package_name::AbstractString
    subst::Vector{Pair{UStrings, UStrings}}
    blacklist::Vector{UStrings}
    os::Union{Vector{String}, Nothing}
end

function BotConfig(package_name::AbstractString; subst::AbstractVector = Vector{Pair{UStrings, UStrings}}(), blacklist::AbstractVector= UStrings[], os::Union{Vector{String}, Nothing} = nothing)
    return BotConfig(package_name, subst, blacklist, os)
end

include("bot/botutils.jl")
include("bot/precompile_include.jl")
include("bot/(de)activator.jl")
include("bot/snoopi_bot.jl")
include("bot/snoopi_bench.jl")


# deprecation and backward compatiblity
macro snoopiBot(args...)
     f, l = __source__.file, __source__.line
     Base.depwarn("`@snoopiBot` at $f:$l is deprecated, rename the macro to `@snoopi_bot`.", Symbol("@snoopiBot"))
     return esc(:(@snoopi_bot($(args...))))
end
macro snoopiBench(args...)
    f, l = __source__.file, __source__.line
    Base.depwarn("`@snoopiBench` at $f:$l is deprecated, rename the macro to `@snoopi_bench`.", Symbol("@snoopiBench"))
    return esc(:(@snoopi_bench($(args...))))
end

@eval @deprecate $(Symbol("@snoopiBot")) $(Symbol("@snoopi_bot"))
@eval @deprecate $(Symbol("@snoopiBench")) $(Symbol("@snoopi_bench"))
