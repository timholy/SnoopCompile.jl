using Pkg
rootdir = dirname(@__DIR__)
Pkg.develop([
  PackageSpec(path=joinpath(rootdir,"SnoopCompileCore")),
  PackageSpec(path=rootdir),
])
