################################################################
import Pkg
"""
Should be removed once Pkg allows adding test dependencies to the current environment

Used in Github Action workflow yaml file
"""
function addtestdep()
    if isfile("test/Test.toml")
        testToml = Pkg.Types.parse_toml("test/Test.toml")
    else
        error("please add a Test.toml to the /test directory for test dependencies")
    end

    for (name, uuid) in testToml["deps"]
        Pkg.add(Pkg.PackageSpec(name = name, uuid = uuid))
    end
end
