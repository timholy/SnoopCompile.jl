
################################################################
"""
    @snoopi_bot config::BotConfig snoopScript

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
macro snoopi_bot(config::BotConfig, snoopScript)

    packageName = config.packageName
    blacklist = config.blacklist
    subst = config.subst
    ################################################################
    packagePath = joinpath(pwd(),"src","$packageName.jl")
    precompilePath, precompileFolder = precompile_pather(packageName)

    quote
        packageSym = Symbol($packageName)
        ################################################################
        using SnoopCompile
        ################################################################
        precompile_deactivator($packagePath, $precompilePath);
        ################################################################

        ### Log the compiles
        data = @snoopi begin
            $(esc(snoopScript))
        end

        ################################################################
        ### Parse the compiles and generate precompilation scripts
        pc = SnoopCompile.parcel(data, subst = $subst, blacklist = $blacklist)
        onlypackage = Dict( packageSym => sort(pc[packageSym]) )
        SnoopCompile.write($precompileFolder,onlypackage)
        ################################################################
        precompile_activator($packagePath, $precompilePath)
    end

end

macro snoopi_bot(packageName::String, snoopScript)
    config = BotConfig(packageName)
    return quote
        @snoopi_bot $config $(esc(snoopScript))
    end
end
macro snoopi_bot(configExpr, snoopScript)
    config = eval(configExpr)
    return quote
        @snoopi_bot $config $(esc(snoopScript))
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

    packageName = config.packageName

    package = Symbol(packageName)
    snoopScript = esc(quote
        using $(package)
        runtestpath = joinpath(dirname(dirname(pathof( $package ))), "test", "runtests.jl")
        include(runtestpath)
    end)
    return quote
        @snoopi_bot $config $(esc(snoopScript))
    end
end

macro snoopi_bot(packageName::String)
    config = BotConfig(packageName)
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
