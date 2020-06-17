module SnoopCompile

using SnoopCompileCore
export @snoopc

using SnoopCompileAnalysis

if isdefined(SnoopCompileCore, Symbol("@snoopi"))
    export @snoopi
    using SnoopCompileAnalysis: parcel, read, write, parse_call, topmodule, lookup_kwbody_ex, exclusions_remover!, format_userimg
end

if isdefined(SnoopCompileCore, Symbol("@snoopr"))
    export @snoopr, invalidation_trees, filtermod, findcaller
    using SnoopCompileAnalysis: getroot
end

using SnoopCompileBot
export BotConfig, snoop_bot, snoop_bench
export timesum, pathof_noload, GoodPath
if isdefined(SnoopCompileBot, Symbol("@snoopiBench"))
    # deprecated names
    export @snoopiBench, @snoopiBot, @snoopi_bench, @snoopi_bot
end

export SnoopCompileCore, SnoopCompileAnalysis, SnoopCompileBot

end # module
