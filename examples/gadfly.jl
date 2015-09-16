# After first running snoop_on(), open a new julia session and run this

if !isinteractive()
    error("Because Gadfly uses the display, you must run this interactively")
end

using SnoopCompile, Gadfly

SnoopCompile.@snoop1 "/tmp/gadfly_compiles.csv" begin
    include(Pkg.dir("Gadfly", "test","runtests.jl"))
end

snoop_off()

data = SnoopCompile.read("/tmp/gadfly_compiles.csv")
pc, discards = SnoopCompile.parcel(data[end:-1:1,2])
SnoopCompile.write("/tmp/precompile", pc)
