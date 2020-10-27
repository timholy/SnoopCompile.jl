module SnoopCompileCore

using Core: MethodInstance, CodeInfo

# @snoopi and @snoopc are exported from their files of definition


include("snoopc.jl")

if VERSION >= v"1.2.0-DEV.573"
    include("snoopi.jl")
end

if VERSION >= v"1.6.0-DEV.1190"  # https://github.com/JuliaLang/julia/pull/37749
    include("snoopi_deep.jl")
end

if VERSION >= v"1.6.0-DEV.154"
    include("snoopr.jl")
end

if VERSION >= v"1.6.0-DEV.1192"  # https://github.com/JuliaLang/julia/pull/37136
    include("snoopl.jl")
end

if VERSION >= v"1.6.0-DEV.1192"  # https://github.com/JuliaLang/julia/pull/37136
    include("snoop_all.jl")
end

end
