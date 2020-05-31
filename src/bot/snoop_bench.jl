# Snooping functions
function _snoopi_bench(snoop_script)
    # quote end generates $ which doesn't work in commands
    # TODO no escape is done for snoop_script!!!
    # TODO
    # data = Core.eval(  $test_modul, _snoopi($(esc(snoop_script)))  )
    # TODO use code directly for now
    # no filter in the benchmark
    return """
        using SnoopCompile
        global SnoopCompile_ENV = true

        empty!(SnoopCompile.__inf_timing__)
        SnoopCompile.start_timing()
        try
            $(string(snoop_script));
        finally
            SnoopCompile.stop_timing()
        end
        data = SnoopCompile.sort_timed_inf(0.0)
        
        @info( "\n Inference time (ms): \t" * string(timesum(data, :ms)))
        global SnoopCompile_ENV = false
    """
end

function _snoopv_bench(snoop_script, package_name)
    return """
        using $package_name
        @timev begin
            $(string(snoop_script));
        end
        @info("The above is @timev result (This has some noise).")
    """
end

function _snoop_bench(config::BotConfig, snoop_script::Expr, test_modul::Module = Main; snooping_type::Symbol)

    package_name = config.package_name
    package_path = config.package_path
    
    # automatic (based on Julia version)
    if snooping_type == :auto
        if VERSION < v"1.2"
            snooping_type = :snoopv
        else
            snooping_type = :snoopi
        end
    end

    if snooping_type == :snoopi
        snooping_code = _snoopi_bench(snoop_script)
    elseif snooping_type == :snoopv
        snooping_code = _snoopv_bench(snoop_script, package_name)
    else
        error("snooping_type $snooping_type is unkown")
    end
    
    ################################################################
    julia_cmd = `julia --project=@. -e $snooping_code`

    out = quote
        package_sym = Symbol($package_name)
        ################################################################
        using SnoopCompile
        @info("""------------------------
        Benchmark Started
        ------------------------
        """)
        ################################################################
        @info("""------------------------
        Precompile Deactivated Benchmark
        ------------------------
        """)
        SnoopCompile.precompile_deactivator($package_path);
        ### Log the compiles
        run($julia_cmd)
        ################################################################
        @info("""------------------------
        Precompile Activated Benchmark
        ------------------------
        """)
        SnoopCompile.precompile_activator($package_path);
        ### Log the compiles
        run($julia_cmd)
        @info("""------------------------
        Benchmark Finished
        ------------------------
        """)
    end
    return out
end

function _snoop_bench(config::BotConfig, test_modul::Module = Main; snooping_type::Symbol)

    package_name = config.package_name
    package_rootpath = dirname(dirname(config.package_path))

    package = Symbol(package_name)
    runtestpath = "$package_rootpath/test/runtests.jl"

    snoop_script = quote
        using $(package);
        include($runtestpath);
    end
    out = _snoop_bench(config, snoop_script, test_modul; snooping_type = snooping_type)
    return out
end

################################################################
"""
    snoop_bench(config::BotConfig, path_to_exmple_script::String, test_modul::Module = Main)

Performs an inference time benchmark by activation and deactivation of the precompilation.

This function chooses the snooping type based on the Julia version.

See the https://timholy.github.io/SnoopCompile.jl/stable/bot/ for more information.

# Arguments:
- config: see [`BotConfg`](@ref)
- path_to_exmple_script: Try to make an absolute path using `@__DIR__` and `pathof_noload`. If the bot doesn't find the script right away, it will search for it.

# Example
```julia
using SnoopCompile

# exmaple_script.jl is in the same directory that the macro is called.
snoop_bench( BotConfig("MatLang"), "\$(@__DIR__)/exmaple_script.jl")
```

```julia
using SnoopCompile

# exmaple_script.jl is at "deps/SnoopCompile/example_script.jl"
example_path = joinpath(dirname(dirname(pathof_noload("MatLang"))), "deps", "SnoopCompile", "example_script.jl")

snoop_bench( BotConfig("MatLang"), example_path)
```

```julia
using SnoopCompile

# exmaple_script.jl is at "src/example_script.jl"
example_path = joinpath(dirname(dirname(pathof_noload("MatLang"))), "src", "example_script.jl")
snoop_bench( BotConfig("MatLang"), example_path)
```
"""
function snoop_bench(config::BotConfig, path_to_exmple_script::String, test_modul::Module  = Main; snooping_type::Symbol = :auto)
    # search for the script! - needed because of confusing paths when referencing pattern_or_file in CI
    path_to_exmple_script = searchdirsboth([pwd(),dirname(dirname(config.package_path))], path_to_exmple_script)
    snoop_script = quote
        include($path_to_exmple_script)
    end
    out = _snoop_bench(config, snoop_script, test_modul; snooping_type = snooping_type)
    Core.eval( test_modul, out )
end

"""
    snoop_bench(config::BotConfig, test_modul::Module = Main)

If you do not have additional examples, you can use your runtests.jl file:

# Example
```julia
using SnoopCompile

# using runtests:
snoop_bench( BotConfig("MatLang") )
```

To selectively exclude some of your tests from running by SnoopCompile bot, use the global SnoopCompile_ENV::Bool variable.
```julia
if !isdefined(Main, :SnoopCompile_ENV) || SnoopCompile_ENV == false
    # the tests you want to skip
end
```
"""
function snoop_bench(config::BotConfig, test_modul::Module = Main; snooping_type::Symbol = :auto)
    out = _snoop_bench(config, test_modul; snooping_type = snooping_type)
    Core.eval( test_modul, out )
end

"""
    snoop_bench(config::BotConfig, expression::Expr, test_modul::Module = Main)

You can pass an expression directly. This is useful for simple expressions like `:(using MatLang)`.

However:

!!! warning
    Don't use this for complex expressions. The functionality isn't guaranteed. Especially if you
    - interpolate into it
    - use macros directly inside it
"""
function snoop_bench(config::BotConfig, snoop_script::Expr, test_modul::Module  = Main; snooping_type::Symbol = :auto)
    out = _snoop_bench(config, snoop_script, test_modul; snooping_type = snooping_type)
    Core.eval( test_modul, out )
end

################################################################
"""
Similar to [`snoop_bench`](@ref) but uses `snoopi` specifically.
"""
function snoopi_bench(args...)
    snoop_bench(args...; snooping_type = :snoopi)
end

"""
Similar to [`snoop_bench`](@ref) but uses `timev` specifically.
"""
function snoopv_bench(args...)
    snoop_bench(args...; snooping_type = :snoopv)
end
################################################################
