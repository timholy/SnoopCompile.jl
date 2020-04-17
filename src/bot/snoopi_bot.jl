
################################################################
"""
    @snoopi_bot config::BotConfig snoop_script

macro that generates precompile files and includes them in the package. Calls other bot functions.

# Examples

`@snoopi_bot` the examples that call the package functions.

```julia
using SnoopCompile

@snoopi_bot "MatLang" begin
  using MatLang
  examplePath = joinpath(dirname(dirname(pathof(MatLang))), "examples")
  include(joinpath(examplePath,"Language_Fundamentals", "usage_Entering_Commands.jl"))
  include(joinpath(examplePath,"Language_Fundamentals", "usage_Matrices_and_Arrays.jl"))
  include(joinpath(examplePath,"Language_Fundamentals", "Data_Types", "usage_Numeric_Types.jl"))
end
```
"""
macro snoopi_bot(config::BotConfig, snoop_script)

    package_name = config.package_name
    blacklist = config.blacklist
    subst = config.subst
    os = config.os
    else_os = config.else_os
    version = config.version
    else_version = config.else_version
    ################################################################
    package_path = joinpath(pwd(),"src","$package_name.jl")

    new_includer_file(package_name, package_path, os, else_os, version, else_version) # create an precompile includer file
    add_includer(package_name, package_path) # add the code to packages source for including the includer

    # precompile folder for writing
    if  isnothing(os)
        if isnothing(version)
            precompile_folder = "$(pwd())/deps/SnoopCompile/precompile/"
        else
            precompile_folder = "$(pwd())/deps/SnoopCompile/precompile/$(VERSION)"
        end
    else
        if isnothing(version)
            precompile_folder = "$(pwd())/deps/SnoopCompile/precompile/$(detectOS()[1])"
        else
            precompile_folder = "$(pwd())/deps/SnoopCompile/precompile/$( detectOS()[1])/$(VERSION)"
        end
    end

    quote
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
end

macro snoopi_bot(package_name::String, snoop_script)
    config = BotConfig(package_name)
    return quote
        @snoopi_bot $config $(esc(snoop_script))
    end
end
macro snoopi_bot(configExpr, snoop_script)
    config = eval(configExpr)
    return quote
        @snoopi_bot $config $(esc(snoop_script))
    end
end

"""
    @snoopi_bot config::BotConfig

If you do not have additional examples, you can use your runtests.jl file. To do that use:

```julia
using SnoopCompile

# using runtests:
@snoopi_bot "MatLang"
```
"""
macro snoopi_bot(config::BotConfig)

    package_name = config.package_name

    package = Symbol(package_name)
    snoop_script = esc(quote
        using $(package)
        runtestpath = joinpath(dirname(dirname(pathof( $package ))), "test", "runtests.jl")
        include(runtestpath)
    end)
    return quote
        @snoopi_bot $config $(esc(snoop_script))
    end
end

macro snoopi_bot(package_name::String)
    config = BotConfig(package_name)
    return quote
        @snoopi_bot $config
    end
end

macro snoopi_bot(configExpr)
    config = eval(configExpr)
    return quote
        @snoopi_bot $config
    end
end
