module SnoopCompileCore

using Core: MethodInstance, CodeInfo

include("snoop_inference.jl")
include("snoop_invalidations.jl")
include("snoop_llvm.jl")

end
