
"""
    precompile_activator(package_path)

Activates precompile of a package by setting `should_precompile = true`

`package_path` is the same as `pathof`. However, `pathof(module)` isn't used to prevent loadnig the package.
"""
function precompile_activator(package_path::String)
    includer_file = joinpath(dirname(package_path), "precompile_includer.jl")
    if !isfile(includer_file)
        error("$includer_file doesn't exists")
    else
        file_text = Base.read(includer_file, String)
        m = match(r"^should_precompile\s*=\s*(true|false)", file_text)
        if m !== nothing
            file_text = replace(file_text, m=>s"true\1")
            Base.write(includer_file, file_text)
        else
            error("\"should_precompile = ...\" doesn't exist")
        end
    end
end

"""
    precompile_deactivator(package_path)

Deactivates precompile of a package by setting `should_precompile = false`

`package_path` is the same as `pathof`. However, `pathof(module)` isn't used to prevent loadnig the package.
"""
function precompile_deactivator(package_path::String)
    includer_file = joinpath(dirname(package_path), "precompile_includer.jl")
    if !isfile(includer_file)
        error("$includer_file doesn't exists")
    else
        file_text = Base.read(includer_file, String)
        m = match(r"^should_precompile\s*=\s*(true|false)", file_text)
        if m !== nothing
            file_text = replace(file_text, m=>s"false\1")
            Base.write(includer_file, file_text)
        else
            error("\"should_precompile = ...\" doesn't exist")
        end
    end
end
