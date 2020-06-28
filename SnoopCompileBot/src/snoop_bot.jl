# Snooping functions
function _snoopi_bot(snoop_script, tmin)
    return quote
        using Pkg; Pkg.add("SnoopCompileCore")
        using SnoopCompileCore

        data = @snoopi tmin=$tmin begin
            $snoop_script
        end
    end
end

function _snoopc_bot(snoop_script)
    return quote
        using Pkg; Pkg.add("SnoopCompileCore")
        using SnoopCompileCore

        @snoopc "compiles.log" begin
            $snoop_script
        end

        using Pkg; Pkg.add("SnoopCompileAnalysis")
        using SnoopCompileAnalysis

        data = SnoopCompileAnalysis.read("compiles.log")[2]
        Base.rm("compiles.log", force = true)
    end
end

function _snoop_analysis_bot(snooping_code, package_name, precompile_folder, subst, exclusions, check_eval)
    return quote
        packageSym = Symbol($package_name)

        ################################################################
        @info "Processsing the generated precompile signatures"

        using Pkg; Pkg.add("SnoopCompileAnalysis")
        using SnoopCompileAnalysis

        ### Parse the compiles and generate precompilation scripts
        pc = SnoopCompileAnalysis.parcel(data; subst = $subst, exclusions = $exclusions, check_eval = $check_eval)
        if !haskey(pc, packageSym)
            @error "no precompile signature is found for $($package_name). Don't load the package before snooping. Restart your Julia session."
        end
        onlypackage = Dict( packageSym => sort(pc[packageSym]) )
        SnoopCompileAnalysis.write($precompile_folder, onlypackage)
        @info "precompile signatures were written to $($precompile_folder)"
    end
end

function _snoop_bot_expr(config::BotConfig, snoop_script, test_modul::Module; snoop_mode::Symbol)
    package_name = config.package_name
    exclusions = config.exclusions
    check_eval = config.check_eval
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
    if snoop_mode == :auto
        if VERSION < v"1.2"
            snoop_mode = :snoopc
        else
            snoop_mode = :snoopi
        end
    end

    if snoop_mode == :snoopi
        snooping_code = _snoopi_bot(snoop_script, tmin)
    elseif snoop_mode == :snoopc
        snooping_code = _snoopc_bot(snoop_script)
    else
        error("snoop_mode $snoop_mode is unkown")
    end
    snooping_code = toplevel_string(snooping_code)

    analysis_code = _snoop_analysis_bot(snooping_code, package_name, precompile_folder, subst, exclusions, check_eval)
    analysis_code = toplevel_string(analysis_code)

    snooping_analysis_code = "$snooping_code; $analysis_code;"

    julia_cmd = `julia --project=@. -e $snooping_analysis_code`

    SnoopCompileBot_path = "$(dirname(@__DIR__))"
    out = quote
        ################################################################
        if !isdefined($test_modul, :SnoopCompileBot)
            using Pkg; Pkg.develop(PackageSpec(path=$SnoopCompileBot_path))
            using SnoopCompileBot
        end

        # Environment variable to detect SnoopCompile bot
        global SnoopCompile_ENV = true

        ################################################################
        SnoopCompileBot.precompile_deactivator($package_path);
        ################################################################

        ### Log the compiles and analyze the compiles
        run($julia_cmd)

        ################################################################
        SnoopCompileBot.precompile_activator($package_path)

        global SnoopCompile_ENV = false
    end
    return out
end

function _snoop_bot_expr(config::BotConfig, test_modul::Module; snoop_mode::Symbol)

    package_name = config.package_name
    package_rootpath = dirname(dirname(pathof_noload(package_name)))
    runtestpath = "$package_rootpath/test/runtests.jl"

    package = Symbol(package_name)
    snoop_script = quote
        using $(package)
        include($runtestpath)
    end
    return _snoop_bot_expr(config, snoop_script, test_modul; snoop_mode = snoop_mode)
end

################################################################

"""
    snoop_bot(config::BotConfig, path_to_example_script::String, test_modul=Main; snoop_mode=:auto)

Generate precompile statements using a precompile script.
`config` can be generated by [`BotConfig`](@ref).
`path_to_example_script` is preferred to be an absolute path.
The example script will be run in the module specified by `test_modul`.
`snoop_mode` can be `:auto`, `:snoopi` (to run [`SnoopCompileCore.@snoopi`](@ref)),
or `:snoopc` (to run [`SnoopCompileCore.@snoopc`](@ref)),
where `:auto` chooses `:snoopi` on supported versions of Julia.

See the [online documentation](https://timholy.github.io/SnoopCompile.jl/stable/bot/)
for a more complete overview.

# Extended help

## Example

In this case, the bot-running script is placed in the same directory as the
precompile script, so we can use `@__DIR__` to find it:

```julia
using SnoopCompile

snoop_bot(BotConfig("MatLang"), "\$(@__DIR__)/example_script.jl")
```
"""
function snoop_bot(config::BotConfig, path_to_example_script::String, test_modul::Module=Main; snoop_mode::Symbol=:auto)
    # search for the script! - needed because of confusing paths when referencing pattern_or_file in CI
    path_to_example_script = searchdirsboth([pwd(),dirname(dirname(config.package_path))], path_to_example_script)
    snoop_script = quote
        include($path_to_example_script)
    end
    out =  _snoop_bot_expr(config, snoop_script, test_modul; snoop_mode=snoop_mode)
    Core.eval( test_modul, out )
end

################################################################
"""
    snoop_bot(config::BotConfig, test_modul::Module = Main)

Generate precompile statements using the package's `runtests.jl` file.

During snooping, `snoop_bot` sets the global variable `SnoopCompile_ENV` to `true`.
If needed, your `runtests.jl` can check for the existence and value of this variable to
customize test behavior specifically for snooping.
"""
function snoop_bot(config::BotConfig, test_modul::Module = Main; snoop_mode::Symbol = :auto)
    out = _snoop_bot_expr(config, test_modul; snoop_mode = snoop_mode)
    Core.eval( test_modul, out )
end

################################################################

"""
    snoop_bot(config::BotConfig, expression::Expr, test_modul::Module = Main)

Generate precompile statements by evaluating an expression, for example `:(using MyPackage)`.
Interpolation and macros are not supported.
"""
function snoop_bot(config::BotConfig, snoop_script::Expr, test_modul::Module  = Main; snoop_mode::Symbol = :auto)
    out = _snoop_bot_expr(config, snoop_script, test_modul; snoop_mode = snoop_mode)
    Core.eval( test_modul, out )
end
