export GoodPath
# to convert WindowsPath before they get inside the SnoopCompile code
GoodPath(x::String) = replace(x, "\\" => "/")
goodjoinpath(args...) = GoodPath(joinpath(args...))
################################################################

export pathof_noload

"""
Returns a package's path without loading the package in the main Julia process.
# Examples
```julia
pathof_noload("MatLang")
```
"""
function pathof_noload(package_name::String)
    path = Base.find_package(package_name)
    if isnothing(path)
        cmd = "import $package_name; print(pathof($package_name))"
        try
            path = Base.read(`julia -e $cmd`, String)
            return GoodPath(path)
        catch
            try
                path = Base.read(`julia --project=@. -e $cmd`, String)
                return GoodPath(path)
            catch
                @error "Couldn't find the path of $package_name"
            end
        end
    else
        return GoodPath(path)
    end
end

################################################################

import Pkg
"""
Should be removed once Pkg allows adding test dependencies to the current environment

Used in Github Action workflow yaml file
"""
function addtestdep()

    if isfile("test/Test.toml")
        toml = Pkg.TOML.parsefile("test/Test.toml")
        test_deps = get(toml, "deps", nothing)
    elseif isfile("test/Project.toml")
        toml = Pkg.TOML.parsefile("test/Project.toml")
        test_deps = get(toml, "deps", nothing)
    else
        toml = Pkg.TOML.parsefile("Project.toml")
        test_deps = get(toml, "extras", nothing)
    end

    if !isnothing(test_deps)
        for (name, uuid) in test_deps
            Pkg.add(Pkg.PackageSpec(name = name, uuid = uuid))
        end
    end
end
