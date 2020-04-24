function snoopi_bot(config::BotConfig, snoop_script)

    package_name = config.package_name
    blacklist = config.blacklist
    subst = config.subst
    os = config.os
    else_os = config.else_os
    version = config.version
    else_version = config.else_version
    ################################################################
    package_path = pathof_noload(package_name)
    package_rootpath = dirname(dirname(package_path))
    precompiles_rootpath = "$package_rootpath/deps/SnoopCompile/precompile/"

    new_includer_file(package_name, package_path, os, else_os, version, else_version) # create an precompile includer file
    add_includer(package_name, package_path) # add the code to packages source for including the includer

    # precompile folder for writing
    if  isnothing(os)
        if isnothing(version)
            precompile_folder = precompiles_rootpath
        else
            precompile_folder = "$precompiles_rootpath/$(VERSION)"
        end
    else
        if isnothing(version)
            precompile_folder = "$precompiles_rootpath/$(detectOS()[1])"
        else
            precompile_folder = "$precompiles_rootpath/$( detectOS()[1])/$(VERSION)"
        end
    end

    out = quote
        packageSym = Symbol($package_name)
        ################################################################
        using SnoopCompile
        ################################################################
        precompile_deactivator($package_path);
        ################################################################

        ### Log the compiles
        data = @snoopi begin
            $(esc(snoop_script))
        end

        ################################################################
        ### Parse the compiles and generate precompilation scripts
        pc = SnoopCompile.parcel(data, subst = $subst, blacklist = $blacklist)
        onlypackage = Dict( packageSym => sort(pc[packageSym]) )
        SnoopCompile.write($precompile_folder,onlypackage)
        ################################################################
        precompile_activator($package_path)
    end
    return out
end


"""
    @snoopi_bot config::BotConfig  snoop_script::Expr

macro that generates precompile files and includes them in the package. Calls other bot functions.

# Examples

`@snoopi_bot` the examples that call the package functions.

```julia
using SnoopCompile

@snoopi_bot BotConfig("MatLang") begin
  using MatLang
  examplePath = joinpath(dirname(dirname(pathof(MatLang))), "examples")
  include(joinpath(examplePath,"Language_Fundamentals", "usage_Entering_Commands.jl"))
  include(joinpath(examplePath,"Language_Fundamentals", "usage_Matrices_and_Arrays.jl"))
  include(joinpath(examplePath,"Language_Fundamentals", "Data_Types", "usage_Numeric_Types.jl"))
end
```
"""
macro snoopi_bot(configExpr, snoop_script)
    config = eval(configExpr)

    out = snoopi_bot(config, snoop_script)
    return out
end

macro snoopi_bot(package_name::String, snoop_script)
    f, l = __source__.file, __source__.line
    @warn "Replace `\"$package_name\"` with `BotConfig(\"$package_name\")`. That syntax will be deprecated in future versions. \n Happens at $f:$l"

    config = BotConfig(package_name)

    out = snoopi_bot(config, snoop_script)
    return out
end

################################################################

function snoopi_bot(config::BotConfig)

    package_name = config.package_name
    package_rootpath = dirname(dirname(pathof_noload(package_name)))
    runtestpath = joinpath(package_rootpath, "test", "runtests.jl");

    package = Symbol(package_name)
    snoop_script = quote
        using $(package)
        include($runtestpath)
    end
    out = snoopi_bot(config, snoop_script)
    return out
end


"""
    @snoopi_bot config::BotConfig

If you do not have additional examples, you can use your runtests.jl file. To do that use:

```julia
using SnoopCompile

# using runtests:
@snoopi_bot BotConfig("MatLang")
```
"""
macro snoopi_bot(configExpr)
    config = eval(configExpr)

    out = snoopi_bot(config)
    return out
end

macro snoopi_bot(package_name::String)
    f, l = __source__.file, __source__.line
    @warn "Replace `\"$package_name\"` with `BotConfig(\"$package_name\")`. That syntax will be deprecated in future versions. \n Happens at $f:$l"

    config = BotConfig(package_name)

    out = snoopi_bot(config)
    return out
end
