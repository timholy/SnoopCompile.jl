using Pkg
rootdir = @__DIR__
Pkg.develop(PackageSpec(path=joinpath(rootdir,"SnoopCompileCore")))
Pkg.develop(PackageSpec(path=joinpath(rootdir,"SnoopCompileAnalysis")))
Pkg.develop(PackageSpec(path=joinpath(rootdir,"SnoopCompileBot")))
Pkg.develop(PackageSpec(path=rootdir))
