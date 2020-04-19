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
