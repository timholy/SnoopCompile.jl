using SnoopCompile

### Log the compiles
# This only needs to be run once (to generate "/tmp/colortypes_compiles.csv")

SnoopCompile.@snoop "/tmp/colortypes_compiles.csv" begin
    include(Pkg.dir("ColorTypes", "test","runtests.jl"))
end

### Parse the compiles and generate precompilation scripts
# This can be run repeatedly

# IMPORTANT: we must have the module(s) defined for the parcelation
# step, otherwise we will get no precompiles for the Colortypes module
using ColorTypes

data = SnoopCompile.read("/tmp/colortypes_compiles.csv")

# Use these two lines if you want to create precompile functions for
# individual packages
pc, discards = SnoopCompile.parcel(data[end:-1:1,2])
SnoopCompile.write("/tmp/precompile", pc)

# Use these two lines if you want to add to your userimg.jl
pc = SnoopCompile.format_userimg(data[end:-1:1,2])
SnoopCompile.write("/tmp/userimg_ColorTypes.jl", pc)

function notisempty(filename, minlength=1)
    @test isfile(filename)
    @test length(readlines(filename)) >= minlength
end

notisempty("/tmp/precompile/precompile_ColorTypes.jl", 100)
notisempty("/tmp/precompile/precompile_FixedPointNumbers.jl", 2)
notisempty("/tmp/userimg_ColorTypes.jl", 100)
