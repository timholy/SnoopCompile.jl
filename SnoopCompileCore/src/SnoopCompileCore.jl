module SnoopCompileCore

using Core: MethodInstance, CodeInfo

const ReinferUtils = isdefined(Base, :ReinferUtils) ? Base.ReinferUtils : Base.StaticData

include("snoop_inference.jl")
include("snoop_invalidations.jl")
include("snoop_llvm.jl")

end
