using SnoopCompile
using Base.Test

if VERSION >= v"0.5.0-dev"
    # Function as argument
    str = "Base.any($(typeof(identity)), Array{Bool, 1})"
    keep, pcstring, fpath, args = SnoopCompile.parse_call(str)
    @test keep
    @test pcstring == "    precompile(Base.any, (typeof(Base.identity), Array{Bool, 1},))"
    # Anonymous function as argument
    str = "Base.any($(typeof(x->x>0)), Array{Float32, 1})"
    keep, pcstring, fpath, args = SnoopCompile.parse_call(str)
    @test !keep
    # Function as a type
    str = "Base.Sort.sort!(Base.#sort!, Array{Any, 1}, Base.Sort.MergeSortAlg, Base.Order.By{Base.#string})"
    keep, pcstring, fpath, args = SnoopCompile.parse_call(str)
    @test keep
    @test pcstring == "    precompile(Base.Sort.sort!, (Array{Any, 1}, Base.Sort.MergeSortAlg, Base.Order.By{typeof(Base.string)},))"
end

include("colortypes.jl")
