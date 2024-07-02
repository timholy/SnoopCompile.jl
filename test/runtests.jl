using Test
using SnoopCompile

include("snoop_inference.jl")
include("snoop_llvm.jl")
include("snoop_invalidations.jl")

# otherwise-untested demos
retflat = SnoopCompile.flatten_demo()
@test !isempty(retflat.children)
