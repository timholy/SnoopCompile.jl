export precompileActivator, precompileDeactivator, precompilePather, @snoopiBot, @snoopiBenchBot, BotConfig

UStrings = Union{AbstractString,Regex,AbstractChar}
################################################################
"""
    BotConfig

Config object that holds the options and configuration for the snoopCompile bot. This object is fed to the `@snoopiBot`.

# Arguments:
- packageName::String
- subst::Vector{Pair{UStrings, UStrings}} : to replace a packages precompile setences with another's package like ["ImageTest" => "Images"]
- blacklist::Vector{UStrings} : to remove some precompile sentences

# Ustrings ==  Union{AbstractString,Regex,AbstractChar} # every string like type that replace() has a method for.
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
include("bot/precomileInclude.jl")
include("bot/snoopiBot.jl")
include("bot/snoopiBenchBot.jl")
