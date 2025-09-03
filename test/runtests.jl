using Test
using SnoopCompile

if !isempty(ARGS)
    "cthulhu" ∈ ARGS && include("extensions/cthulhu.jl")
    "jet" ∈ ARGS && include("extensions/jet.jl")
else
    include("snoop_inference.jl")
    include("snoop_llvm.jl")
    include("snoop_invalidations_parallel.jl")
    include("snoop_invalidations.jl")

    # otherwise-untested demos
    retflat = SnoopCompile.flatten_demo()
    @test !isempty(retflat.children)
end
