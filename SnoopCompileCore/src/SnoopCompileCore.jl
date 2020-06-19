module SnoopCompileCore

using Core: MethodInstance, CodeInfo

# @snoopi and @snoopc are exported from their files of definition


include("snoopc.jl")

if VERSION >= v"1.2.0-DEV.573"
    include("snoopi.jl")
end


if VERSION >= v"1.6.0-DEV.154"
    include("snoopr.jl")
end

end
