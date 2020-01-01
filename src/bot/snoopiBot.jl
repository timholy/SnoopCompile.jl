
################################################################
"""
    @snoopiBot config::BotConfig snoopScript

macro that generates precompile files and includes them in the package. Calls other bot functions.

# Examples

`@snoopiBot` the examples that call the package functions.

```julia
using SnoopCompile

@snoopiBot "MatLang" begin
  using MatLang
  examplePath = joinpath(dirname(dirname(pathof(MatLang))), "examples")
  include(joinpath(examplePath,"Language_Fundamentals", "usage_Entering_Commands.jl"))
  include(joinpath(examplePath,"Language_Fundamentals", "usage_Matrices_and_Arrays.jl"))
  include(joinpath(examplePath,"Language_Fundamentals", "Data_Types", "usage_Numeric_Types.jl"))
end
```
"""
macro snoopiBot(config::BotConfig, snoopScript)

    packageName = config.packageName
    blacklist = config.blacklist
    subst = config.subst
    ################################################################
    packagePath = joinpath(pwd(),"src","$packageName.jl")
    precompilePath, precompileFolder = precompilePather(packageName)

    quote
        packageSym = Symbol($packageName)
        ################################################################
        using SnoopCompile
        ################################################################
        precompileDeactivator($packagePath, $precompilePath);
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
        precompileActivator($packagePath, $precompilePath)
    end

end

macro snoopiBot(packageName::String, snoopScript)
    config = BotConfig(packageName)
    return quote
        @snoopiBot $config $(esc(snoopScript))
    end
end
macro snoopiBot(configExpr, snoopScript)
    config = eval(configExpr)
    return quote
        @snoopiBot $config $(esc(snoopScript))
    end
end

"""
    @snoopiBot config::BotConfig

If you do not have additional examples, you can use your runtests.jl file. To do that use:

```julia
using SnoopCompile

# using runtests:
@snoopiBot "MatLang"
```
"""
macro snoopiBot(config::BotConfig)

    packageName = config.packageName

    package = Symbol(packageName)
    snoopScript = esc(quote
        using $(package)
        runtestpath = joinpath(dirname(dirname(pathof( $package ))), "test", "runtests.jl")
        include(runtestpath)
    end)
    return quote
        @snoopiBot $config $(esc(snoopScript))
    end
end

macro snoopiBot(packageName::String)
    config = BotConfig(packageName)
    return quote
        @snoopiBot $config
    end
end

macro snoopiBot(configExpr)
    config = eval(configExpr)
    return quote
        @snoopiBot $config
    end
end
