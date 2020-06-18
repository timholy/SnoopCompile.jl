using Pkg
rootdir = dirname(@__DIR__)
Pkg.activate(rootdir)
Pkg.develop(PackageSpec(path=joinpath(rootdir,"SnoopCompileCore")))
Pkg.develop(PackageSpec(path=joinpath(rootdir,"SnoopCompileAnalysis")))
Pkg.develop(PackageSpec(path=joinpath(rootdir,"SnoopCompileBot")))
