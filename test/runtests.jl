using Test
using SnoopCompile

include("snoopi_deep.jl")
include("snoopl.jl")
include("snoopr.jl")

# otherwise-untested demos
retflat = SnoopCompile.flatten_demo()
@test !isempty(retflat.children)
