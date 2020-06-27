using Pkg

rootdir = dirname(@__DIR__)
prev_env = Base.ACTIVE_PROJECT[]

# Add packages to every environment

packages_paths = [joinpath(rootdir,"SnoopCompileCore"), joinpath(rootdir,"SnoopCompileAnalysis"), joinpath(rootdir,"SnoopCompileBot"), rootdir]
envs = [prev_env, "", "."]
for env in envs
  if env !== nothing && !any(occursin.(dirname(env), packages_paths))
    Pkg.activate(env)
    Pkg.develop([
      PackageSpec(path=joinpath(rootdir,"SnoopCompileCore")),
      PackageSpec(path=joinpath(rootdir,"SnoopCompileAnalysis")),
      PackageSpec(path=joinpath(rootdir,"SnoopCompileBot")),
      PackageSpec(path=rootdir),
    ])
    Pkg.resolve()
  end
end

# add every other sub-package to other sub-package
for package_path in packages_paths[1:3]
    Pkg.resolve()
    Pkg.activate(package_path)
    for to_add in setdiff(packages_paths, [package_path])
      try
        Pkg.develop(PackageSpec(path=to_add))
      catch
      end
    end
end
Pkg.resolve()

# add dev version of Bot
Pkg.activate(rootdir)
Pkg.develop(PackageSpec(path=joinpath(rootdir,"SnoopCompileBot")))
Pkg.resolve()

# go back to previous env
if prev_env !== nothing
  Pkg.activate(prev_env)
else
  Pkg.activate("")
end
