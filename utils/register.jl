using LocalRegistry, Pkg

const __topdir__ = dirname(@__DIR__)

"""
    bump_version(version::VersionNumber)

Bump the version number of all packages in the repository to `version`.
"""
function bump_version(version::VersionNumber)
    for dir in (__topdir__,
                joinpath(__topdir__, "SnoopCompileAnalysis"),
                joinpath(__topdir__, "SnoopCompileBot"),
                joinpath(__topdir__, "SnoopCompileCore"))
        projfile = joinpath(dir, "Project.toml")
        lines = readlines(projfile)
        idxs = findall(str->startswith(str, "version"), lines)
        idx = only(idxs)
        lines[idx] = "version = \"$version\""
        # Find any dependencies on versions within the repo
        idxs = findall(str->str == "[compat]", lines)
        if !isempty(idxs)
            idxcompat = only(idxs)
            idxend = findnext(str->!isempty(str) && str[1] == '[', lines, idxcompat+1)  # first line of next TOML section
            if idxend === nothing
                idxend = length(lines) + 1
            end
            for i = idxcompat:idxend-1
                if startswith(lines[i], "SnoopCompile")
                    strs = split(lines[i], '=')
                    lines[i] = strs[1] * "= \"~" * string(version) * '"'
                end
            end
        end
        open(projfile, "w") do io
            for line in lines
                println(io, line)
            end
        end
    end
    return nothing
end

function register_all()
    for pkg in ("SnoopCompileCore", "SnoopCompileAnalysis", "SnoopCompileBot", "SnoopCompile")
        Pkg.develop(pkg)
        pkgsym = Symbol(pkg)
        @eval Main using $pkgsym
        register(getfield(Main, pkgsym)::Module)
    end
end
