# Snooping functions
function _snoopi_bot(snoop_script, tmin)
    return quote
        # data = Core.eval($test_modul, SnoopCompile._snoopi($(Meta.quot(snoop_script))))
        # TODO use code directly for now
        
        empty!(SnoopCompile.__inf_timing__)
        SnoopCompile.start_timing()
        try
            $snoop_script
        finally
            SnoopCompile.stop_timing()
        end
        data = SnoopCompile.sort_timed_inf($tmin)
    end
end

function _snoopc_bot(snoop_script)
    return quote
        @snoopc "compiles.log" begin
            $snoop_script
        end
        data = SnoopCompile.read("compiles.log")[2]
    end
end

function _snoop_bot(config::BotConfig, snoop_script, test_modul::Module; snooping_type::Symbol)
    package_name = config.package_name
    blacklist = config.blacklist
    exhaustive = config.exhaustive
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
            precompile_folder = "$precompiles_rootpath/$(VersionFloat(VERSION))"
        end
    else
        if isnothing(version)
            precompile_folder = "$precompiles_rootpath/$(detectOS()[1])"
        else
            precompile_folder = "$precompiles_rootpath/$( detectOS()[1])/$(VersionFloat(VERSION))"
        end
    end
    
    # automatic (based on Julia version)
    if snooping_type == :auto
        if VERSION < v"1.2"
            snooping_type = :snoopc
        else
            snooping_type = :snoopi
        end
    end

    if snooping_type == :snoopi
        snooping_code = _snoopi_bot(snoop_script, tmin)
    elseif snooping_type == :snoopc
        snooping_code = _snoopc_bot(snoop_script)
    else
        error("snooping_type $snooping_type is unkown")
    end
    
    out = quote
        packageSym = Symbol($package_name)
        ################################################################
        using SnoopCompile

        # Environment variable to detect SnoopCompile bot
        global SnoopCompile_ENV = true

        ################################################################
        SnoopCompile.precompile_deactivator($package_path);
        ################################################################

        ### Log the compiles
        $snooping_code

        ################################################################
        @info "Processsing the generated precompile signatures"
        ### Parse the compiles and generate precompilation scripts
        pc = SnoopCompile.parcel(data, subst = $subst, blacklist = $blacklist, exhaustive = $exhaustive)
        if !haskey(pc, packageSym)
            @error "no precompile signature is found for $($package_name). Don't load the package before snooping. Restart your Julia session."
        end
        onlypackage = Dict( packageSym => sort(pc[packageSym]) )
        SnoopCompile.write($precompile_folder, onlypackage)
        @info "precompile signatures were written to $($precompile_folder)"
        ################################################################
        SnoopCompile.precompile_activator($package_path)

        global SnoopCompile_ENV = false
    end
    return out
end

function _snoop_bot(config::BotConfig, test_modul::Module; snooping_type::Symbol)

    package_name = config.package_name
    package_rootpath = dirname(dirname(pathof_noload(package_name)))
    runtestpath = "$package_rootpath/test/runtests.jl"

    package = Symbol(package_name)
    snoop_script = quote
        using $(package)
        include($runtestpath)
    end
    return _snoop_bot(config, snoop_script, test_modul; snooping_type = snooping_type)
end

################################################################

"""
    snoop_bot(config::BotConfig, path_to_exmple_script::String, test_modul = Main)

This function automatically generates precompile files and includes them in the package. This macro does most of the operations that `SnoopCompile` is capable of automatically.

This function chooses the snooping type based on the Julia version.

See the https://timholy.github.io/SnoopCompile.jl/stable/bot/ for more information.

# Arguments:
- config: see [`BotConfg`](@ref)
- path_to_exmple_script: Try to make an absolute path using `@__DIR__` and `pathof_noload`. If the bot doesn't find the script right away, it will search for it.

# Example
```julia
using SnoopCompile

# exmaple_script.jl is in the same directory that the macro is called.
snoop_bot( BotConfig("MatLang"), "\$(@__DIR__)/exmaple_script.jl")
```

```julia
using SnoopCompile

# exmaple_script.jl is at "deps/SnoopCompile/example_script.jl"
example_path = joinpath(dirname(dirname(pathof_noload("MatLang"))), "deps", "SnoopCompile", "example_script.jl")

snoop_bot( BotConfig("MatLang"), example_path )
```

```julia
using SnoopCompile

# exmaple_script.jl is at "src/example_script.jl"
example_path = joinpath(dirname(dirname(pathof_noload("MatLang"))), "src", "example_script.jl")
snoop_bot( BotConfig("MatLang"), example_path )
```
"""
function snoop_bot(config::BotConfig, path_to_exmple_script::String, test_modul::Module = Main; snooping_type::Symbol = :auto)
    # search for the script! - needed because of confusing paths when referencing pattern_or_file in CI
    path_to_exmple_script = searchdirsboth([pwd(),dirname(dirname(config.package_path))], path_to_exmple_script)
    snoop_script = quote
        include($path_to_exmple_script)
    end
    out =  _snoop_bot(config, snoop_script, test_modul; snooping_type = snooping_type)
    Core.eval( test_modul, out )
end

################################################################
"""
    snoop_bot(config::BotConfig, test_modul::Module = Main)

If you do not have additional examples, you can use your runtests.jl file:

# Example
```julia
using SnoopCompile

# using runtests:
snoop_bot( BotConfig("MatLang") )
```

To selectively exclude some of your tests from running by SnoopCompile bot, use the global SnoopCompile_ENV::Bool variable.
```julia
if !isdefined(Main, :SnoopCompile_ENV) || SnoopCompile_ENV == false
    # the tests you want to skip in SnoopCompile environment
end
```
"""
function snoop_bot(config::BotConfig, test_modul::Module = Main; snooping_type::Symbol = :auto)
    out = _snoop_bot(config, test_modul; snooping_type = snooping_type)
    Core.eval( test_modul, out )
end

################################################################

"""
    snoop_bot(config::BotConfig, expression::Expr, test_modul::Module = Main)

You can pass an expression directly. This is useful for simple experssions like `:(using MatLang)`.

However:

!!! warning
    Don't use this for complex expressions. The functionality isn't guaranteed. Especially if you
    - interpolate into it
    - use macros directly inside it
"""
function snoop_bot(config::BotConfig, snoop_script::Expr, test_modul::Module  = Main; snooping_type::Symbol = :auto)
    out = _snoop_bot(config, snoop_script, test_modul; snooping_type = snooping_type)
    Core.eval( test_modul, out )
end

################################################################
"""
Similar to [`snoop_bot`](@ref) but uses `snoopi` specifically.
"""
function snoopi_bot(args...)
    snoop_bot(args...; snooping_type = :snoopi)
end

"""
Similar to [`snoop_bot`](@ref) but uses `snoopc` specifically.
"""
function snoopc_bot(args...)
    snoop_bot(args...; snooping_type = :snoopc)
end

################################################################
