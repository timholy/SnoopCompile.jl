using SnoopCompile
using Base.Test

if VERSION >= v"0.5.0-dev"
    # Function as argument
    keep, pcstring, fpath, args = SnoopCompile.parse_call("Base.any($(typeof(identity)), Array{Bool, 1})")
    @test keep
    @test pcstring == "    precompile(Base.any, (typeof(Base.identity), Array{Bool, 1},))"
    # Anonymous function as argument
    keep, pcstring, fpath, args = SnoopCompile.parse_call("Base.any($(typeof(x->x>0)), Array{Float32, 1})")
    @test !keep
end

include("colortypes.jl")
