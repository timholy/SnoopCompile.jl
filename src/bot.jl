export precompileActivator, precompileDeactivator, precompilePather, @snoopiBot, @snoopiBenchBot, BotConfig

################################################################
"""
    BotConfig

Config object that holds the options and configuration for the snoopCompile bot. This object is fed to the `@snoopiBot`.
"""
struct BotConfig
    packageName::String
    blacklist::Vector{Union{AbstractString,Regex,AbstractChar}}
end

BotConfig(packageName::String) = BotConfig(packageName, String[])

include("botutils.jl")
include("precomileInclude.jl")
include("snoopiBot.jl")
include("snoopiBenchBot.jl")
