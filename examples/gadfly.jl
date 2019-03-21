# For this to work, you need to be able to run
#     using Gadfly
#     include(joinpath(dirname(dirname(pathof(Gadfly))), "test", "runtests.jl"))
# successfully. Even if you have the Gadfly package, you may need to add packages.

# Open a new julia session and run this:

using SnoopCompile

SnoopCompile.@snoopc "/tmp/gadfly_compiles.csv" begin
    using Gadfly, Pkg
    include(joinpath(dirname(dirname(pathof(Gadfly))), "test", "runtests.jl"))
end

data = SnoopCompile.read("/tmp/gadfly_compiles.csv")
pc = SnoopCompile.parcel(reverse!(data[2]))
SnoopCompile.write("/tmp/precompile", pc)
