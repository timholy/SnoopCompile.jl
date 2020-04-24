function _snoopi_bot(config::BotConfig, snoop_script, test_modul::Module)
    package_name = config.package_name
    blacklist = config.blacklist
    os = config.os
    else_os = config.else_os
    version = config.version
    else_version = config.else_version
    package_path = config.package_path
    precompiles_rootpath = config.precompiles_rootpath
    subst = config.subst
    tmin = config.tmin

    if test_modul != Main && string(test_modul) == package_name
        @error "Your example/test shouldn't be in the same module!. Use `Main` instead."
    end

    ################################################################
    package_rootpath = dirname(dirname(package_path))

    new_includer_file(package_name, package_path, precompiles_rootpath, os, else_os, version, else_version) # create an precompile includer file
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
        SnoopCompile.precompile_deactivator($package_path);
        ################################################################

        ### Log the compiles
        # data = Core.eval($test_modul, SnoopCompile.snoopi($(Meta.quot(snoop_script))))
        # TODO use code directly for now
        empty!(SnoopCompile.__inf_timing__)
        SnoopCompile.start_timing()
        try
            $snoop_script
        finally
            SnoopCompile.stop_timing()
        end
        data = SnoopCompile.sort_timed_inf($tmin)

        ################################################################
        ### Parse the compiles and generate precompilation scripts
        pc = SnoopCompile.parcel(data, subst = $subst, blacklist = $blacklist)
        if !haskey(pc, packageSym)
            @error "no precompile signature is found for $package_name. Don't load the package before snooping. Restart your Julia session."
        end
        onlypackage = Dict( packageSym => sort(pc[packageSym]) )
        SnoopCompile.write($precompile_folder, onlypackage)
        ################################################################
        SnoopCompile.precompile_activator($package_path)
    end
    return out
end

function _snoopi_bot(config::BotConfig, test_modul::Module)

    package_name = config.package_name
    package_rootpath = dirname(dirname(pathof_noload(package_name)))
    runtestpath = "$package_rootpath/test/runtests.jl"

    package = Symbol(package_name)
    snoop_script = quote
        using $(package)
        include($runtestpath)
    end
    return _snoopi_bot(config, snoop_script, test_modul)
end

################################################################

"""
    snoopi_bot(config::BotConfig, path_to_exmple_script::String, test_modul = Main)

This function automatically generates precompile files and includes them in the package. This macro does most of the operations that `SnoopCompile` is capable of automatically.

See the https://timholy.github.io/SnoopCompile.jl/stable/bot/ for more information.

# Arguments:
- config: see [`BotConfg`](@ref)
- path_to_exmple_script: Try to make an absolute path using `@__DIR__` and `pathof_noload`. If the bot doesn't find the script right away, it will search for it.

# Example
```julia
using SnoopCompile

# exmaple_script.jl is in the same directory that the macro is called.
snoopi_bot( BotConfig("MatLang"), "\$(@__DIR__)/exmaple_script.jl")
```

```julia
using SnoopCompile

# exmaple_script.jl is at "deps/SnoopCompile/example_script.jl"
example_path = joinpath(dirname(dirname(pathof_noload("MatLang"))), "deps", "SnoopCompile", "example_script.jl")

snoopi_bot( BotConfig("MatLang"), example_path )
```

```julia
using SnoopCompile

# exmaple_script.jl is at "src/example_script.jl"
example_path = joinpath(dirname(dirname(pathof_noload("MatLang"))), "src", "example_script.jl")
snoopi_bot( BotConfig("MatLang"), example_path )
```
"""
function snoopi_bot(config::BotConfig, path_to_exmple_script::String, test_modul::Module = Main)
    # search for the script! - needed because of confusing paths when referencing pattern_or_file in CI
    path_to_exmple_script = searchdirsboth([pwd(),dirname(dirname(config.package_path))], path_to_exmple_script)
    snoop_script = quote
        include($path_to_exmple_script)
    end
    out =  _snoopi_bot(config, snoop_script, test_modul)
    Core.eval( test_modul, out )
end

################################################################
"""
    snoopi_bot(config::BotConfig, test_modul::Module = Main)

If you do not have additional examples, you can use your runtests.jl file:

# Example
```julia
using SnoopCompile

# using runtests:
snoopi_bot( BotConfig("MatLang") )
```
"""
function snoopi_bot(config::BotConfig, test_modul::Module = Main)
    out = _snoopi_bot(config, test_modul)
    Core.eval( test_modul, out )
end

################################################################

"""
    snoopi_bot(config::BotConfig, expression::Expr, test_modul::Module = Main)

You can pass an expression directly. This is useful for simple experssions like `:(using MatLang)`.

However:

!!! warning
    Don't use this for complex expressions. The functionality isn't guaranteed. Especially if you
    - interpolate into it
    - use macros directly inside it
"""
function snoopi_bot(config::BotConfig, snoop_script::Expr, test_modul::Module  = Main)
    out = _snoopi_bot(config, snoop_script, test_modul)
    Core.eval( test_modul, out )
end

################################################################

"""
    @snoopi_bot config::BotConfig  snoop_script::Expr
    @snoopi_bot config::BotConfig

!!! warning
    This macro isn't recommend. Use the function form instead: `snoopi_bot(config::BotConfig, path_to_exmple_script::String)`.

# Examples
```julia
using SnoopCompile


@snoopi_bot BotConfig("MatLang") begin
  using MatLang
  MatLang_rootpath = dirname(dirname(pathof("MatLang")))

  include("\$MatLang_rootpath/examples/Language_Fundamentals/usage_Matrices_and_Arrays.jl")
  include("\$MatLang_rootpath/examples/Language_Fundamentals/Data_Types/usage_Numeric_Types.jl")
end
```
"""
macro snoopi_bot(configExpr, snoop_script::Expr)
    @warn "This macro isn't recommend. Use the function form instead: `snoopi_bot(config::BotConfig, path_to_exmple_script::String)`."
    config = eval(configExpr)
    out = _snoopi_bot(config, snoop_script, __module__)
    return out
end

macro snoopi_bot(package_name::String, snoop_script::Expr)
    @warn "This macro isn't recommend. Use the function form instead: `snoopi_bot(config::BotConfig, path_to_exmple_script::String)`."

    f, l = __source__.file, __source__.line
    @warn "Replace `\"$package_name\"` with `BotConfig(\"$package_name\")`. That syntax will be deprecated in future versions. \n Happens at $f:$l"

    config = BotConfig(package_name)
    out = _snoopi_bot(config, snoop_script, __module__)
    return out
end

"""
    @snoopi_bot config::BotConfig

!!! warning
    This macro isn't recommend. Use the function form instead: `snoopi_bot(config::BotConfig)`.

Ues tests for snooping:
```julia
@snoopi_bot BotConfig("MatLang")
```
"""
macro snoopi_bot(configExpr)
    @warn "This macro isn't recommend. Use the function form instead: `snoopi_bot(config::BotConfig)`."

    config = eval(configExpr)
    out = _snoopi_bot(config, __module__)
    return out
end

macro snoopi_bot(package_name::String)
    f, l = __source__.file, __source__.line
    @warn "This macro isn't recommend. Use the function form instead: `snoopi_bot(config::BotConfig)`."

    @warn "Replace `\"$package_name\"` with `BotConfig(\"$package_name\")`. That syntax will be deprecated in future versions. \n Happens at $f:$l"

    config = BotConfig(package_name)
    out = _snoopi_bot(config, __module__)
    return out
end
