# Open a new julia session and run this:

using SnoopCompile

SnoopCompile.@snoop1 "/tmp/gadfly_compiles.csv" begin
    include(Pkg.dir("Gadfly", "test","runtests.jl"))
end

data = SnoopCompile.read("/tmp/gadfly_compiles.csv")
pc = SnoopCompile.parcel(reverse!(data[2]))
SnoopCompile.write("/tmp/precompile", pc)
