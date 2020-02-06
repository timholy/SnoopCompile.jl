export precompile_activator, precompile_deactivator, precompile_pather, BotConfig, @snoopi_bot, @snoopi_bench

const UStrings = Union{AbstractString,Regex,AbstractChar}
################################################################
"""
    BotConfig

Config object that holds the options and configuration for the SnoopCompile bot. This object is fed to the `@snoopi_bot`.

# Arguments:
- `packageName::String`
- `subst::Vector{Pair{UStrings, UStrings}}` : to replace a packages precompile setences with another's package like `["ImageTest" => "Images"]`
- `blacklist::Vector{UStrings}` : to remove some precompile sentences

`const UStrings ==  Union{AbstractString,Regex,AbstractChar}` # every string like type that `replace()` has a method for.
"""
struct BotConfig
    packageName::String
    subst::Vector{Pair{T1, T2}} where {T1<:UStrings, T2 <: UStrings}
    blacklist::Vector{T3} where {T3<:UStrings}
end

function BotConfig(packageName::String; subst::Vector{Pair{T1, T2}} where {T1<:UStrings, T2 <: UStrings} = Vector{Pair{String, String}}(), blacklist::Vector{T3} where {T3<:UStrings}= String[])
    return BotConfig(packageName, subst, blacklist)
end

include("bot/botutils.jl")
include("bot/precompileInclude.jl")
include("bot/snoopi_bot.jl")
include("bot/snoopi_bench.jl")


# deprecation and backward compatiblity
macro snoopiBot(args...)
    return esc(:(@snoopi_bot($(args...))))
end
macro snoopiBench(args...)
    return esc(:(@snoopi_bench($(args...))))
end

@eval @deprecate $(Symbol("@snoopiBot")) $(Symbol("@snoopi_bot"))
@eval @deprecate $(Symbol("@snoopiBench")) $(Symbol("@snoopi_bench"))
