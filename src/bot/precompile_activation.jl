
"""
    precompile_activator(package_path)

Activates precompile of a package by setting `should_precompile = true`

`package_path` should be the full path to the defining file for the package, i.e., identical to `pathof(ThePkg)`. However, `pathof(module)` isn't used to prevent the need to load the package.
"""
function precompile_activator(package_path::AbstractString)
    includer_file = joinpath(dirname(package_path), "precompile_includer.jl")
    if !isfile(includer_file)
        error("$includer_file doesn't exists")
    else
        file_text = Base.read(includer_file, String)
        regp = r"(should_precompile\s*=\s*)(true|false)"
        m = match(regp, file_text)
        if m !== nothing
            file_text = replace(file_text, regp => s"\1 true")
            Base.write(includer_file, file_text)
        else
            error("\"should_precompile = ...\" doesn't exist")
        end
    end
end

"""
    precompile_deactivator(package_path)

Deactivates precompile of a package by setting `should_precompile = false`

`package_path` should be the full path to the defining file for the package, i.e., identical to `pathof(ThePkg)`. However, `pathof(module)` isn't used to prevent the need to load the package.
"""
function precompile_deactivator(package_path::AbstractString)
    includer_file = joinpath(dirname(package_path), "precompile_includer.jl")
    if !isfile(includer_file)
        error("$includer_file doesn't exists")
    else
        file_text = Base.read(includer_file, String)
        regp = r"(should_precompile\s*=\s*)(true|false)"
        m = match(regp, file_text)
        if m !== nothing
            file_text = replace(file_text, regp => s"\1 false")
            Base.write(includer_file, file_text)
        else
            error("\"should_precompile = ...\" doesn't exist")
        end
    end
end
