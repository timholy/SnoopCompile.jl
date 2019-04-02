# For this to work, you need to be able to run
#     using Images
#     include(joinpath(dirname(dirname(pathof(Images))), "test", "runtests.jl"))
# successfully. Even if you have the Images package, you may need to add packages.

using SnoopCompile

### Log the compiles
# This only needs to be run once (to generate "/tmp/images_compiles.csv")

SnoopCompile.@snoopc "/tmp/images_compiles.csv" begin
    using Images, Pkg
    include(joinpath(dirname(dirname(pathof(Images))), "test", "runtests.jl"))
end

### Parse the compiles and generate precompilation scripts
# This can be run repeatedly

data = SnoopCompile.read("/tmp/images_compiles.csv")

# Old versions of Images ran the tests inside a module ImagesTest, so all
# the precompiles would get credited to ImagesTest. Credit them to Images instead:
subst = ["ImagesTests"=>"Images", ]

# Blacklist can be used to help fix problems.
# For example, old versions of Julia output would MIME types with invalid syntax:
blacklist = ["MIME", ]

# Use these two lines if you want to create precompile functions for
# individual packages
pc = SnoopCompile.parcel(reverse!(data[2]), subst=subst, blacklist=blacklist)
SnoopCompile.write("/tmp/precompile", pc)

# Use these two lines if you want to add to your userimg.jl
pc = SnoopCompile.format_userimg(reverse!(data[2]), subst=subst, blacklist=blacklist)
SnoopCompile.write("/tmp/userimg_Images.jl", pc)
