################################################################
"""
    timesum(snoop)

Calculates and prints the total time measured by a snoop macro.

It is used inside @snoopi_bench. Julia can cache inference results so to measure the effect of adding _precompile_() sentences generated by snoopi to your package, use the [`@snoopi_bench`](@ref). This benchmark measures inference time taken during loading and running of a package.

# Examples
```julia
using SnoopCompile
data = @snoopi begin
    using MatLang
    MatLang_rootpath = dirname(dirname(pathof("MatLang")))

    include("\$MatLang_rootpath/test/runtests.jl")
end
println(timesum(data))
```

## Manual Benchmark (withtout using [`@snoopi_bench`](@ref))
- dev your package

- comment the precompile part of your package (`include()` and `_precompile_()`)
- run the following benchmark
- restart Julia

- uncomment the precompile part of your package (`include()` and `_precompile_()`)
- run the following benchmark
- restart Julia

### Benchmark
```julia
using SnoopCompile

println("Package load time:")
loadSnoop = @snoopi using MatLang

timesum(loadSnoop)

println("Running Examples/Tests:")
runSnoop = @snoopi begin
    using MatLang

    MatLang_rootpath = dirname(dirname(pathof("MatLang")))
    include("\$MatLang_rootpath/test/runtests.jl")
end

timesum(runSnoop)
```
"""
function timesum(snoop::Vector{Tuple{Float64, Core.MethodInstance}})
    if isempty(snoop)
        return 0.0
    else
        return sum(first, snoop)
    end
end
################################################################
function _snoopi_bench(config::BotConfig, snoop_script::Expr, test_modul::Module = Main)

    package_name = config.package_name
    package_path = config.package_path

    if !isnothing(config.version) && any(config.version .< v"1.2")
        @error "`@snoopi_bench` is only supported for Julia 1.2 and above."
    end
    ################################################################
    # quote end generates $ which doesn't work in commands
    # TODO no escape is done for snoop_script!!!
    # TODO
    # data = Core.eval(  $test_modul, snoopi($(esc(snoop_script)))  )
    # TODO use code directly for now
    # no filter in the benchmark
    juliaCode = """
        using SnoopCompile
        empty!(SnoopCompile.__inf_timing__)
        SnoopCompile.start_timing()
        try
            $(string(snoop_script));
        finally
            SnoopCompile.stop_timing()
        end
        data = SnoopCompile.sort_timed_inf(0.0)
        @info(timesum(data))
    """
    julia_cmd = `julia --project=@. -e $juliaCode`
    out = quote
        package_sym = Symbol($package_name)
        ################################################################
        using SnoopCompile
        @info("""*******************
        Benchmark Started
        *******************
        """)
        ################################################################
        @info("""Precompile Deactivated Inference Benchmark
        ------------------------
        """)
        SnoopCompile.precompile_deactivator($package_path);
        ### Log the compiles
        run($julia_cmd)
        ################################################################
        @info("""Precompile Activated Inference Benchmark
        ------------------------
        """)
        SnoopCompile.precompile_activator($package_path);
        ### Log the compiles
        run($julia_cmd)
        @info("""*******************
        Benchmark Finished
        *******************
        """)
    end
    return out
end

function _snoopi_bench(config::BotConfig, test_modul::Module = Main)

    package_name = config.package_name
    package_rootpath = dirname(dirname(config.package_path))

    package = Symbol(package_name)
    runtestpath = "$package_rootpath/test/runtests.jl"

    snoop_script = quote
        using $(package);
        include($runtestpath);
    end
    out = _snoopi_bench(config, snoop_script, test_modul)
    return out
end

################################################################
"""
    snoopi_bench(config::BotConfig, path_to_exmple_script::String, test_modul::Module = Main)

Performs an inference time benchmark by activation and deactivation of the precompilation.

See the https://timholy.github.io/SnoopCompile.jl/stable/bot/ for more information.

# Arguments:
- config: see [`BotConfg`](@ref)
- path_to_exmple_script: Try to make an absolute path using `@__DIR__` and `pathof_noload`. If the bot doesn't find the script right away, it will search for it.

# Example
```julia
using SnoopCompile

# exmaple_script.jl is in the same directory that the macro is called.
snoopi_bench( BotConfig("MatLang"), "\$(@__DIR__)/exmaple_script.jl")
```

```julia
using SnoopCompile

# exmaple_script.jl is at "deps/SnoopCompile/example_script.jl"
example_path = joinpath(dirname(dirname(pathof_noload("MatLang"))), "deps", "SnoopCompile", "example_script.jl")

snoopi_bench( BotConfig("MatLang"), example_path)
```

```julia
using SnoopCompile

# exmaple_script.jl is at "src/example_script.jl"
example_path = joinpath(dirname(dirname(pathof_noload("MatLang"))), "src", "example_script.jl")
snoopi_bench( BotConfig("MatLang"), example_path)
```
"""
function snoopi_bench(config::BotConfig, path_to_exmple_script::String, test_modul::Module  = Main)
    # search for the script! - needed because of confusing paths when referencing pattern_or_file in CI
    path_to_exmple_script = searchdirsboth([pwd(),dirname(dirname(config.package_path))], path_to_exmple_script)
    snoop_script = quote
        include($path_to_exmple_script)
    end
    out = _snoopi_bench(config, snoop_script, test_modul)
    Core.eval( test_modul, out )
end

"""
    snoopi_bench(config::BotConfig, test_modul::Module = Main)

If you do not have additional examples, you can use your runtests.jl file:

# Example
```julia
using SnoopCompile

# using runtests:
snoopi_bench( BotConfig("MatLang") )
```
"""
function snoopi_bench(config::BotConfig, test_modul::Module = Main)
    out = _snoopi_bench(config, test_modul)
    Core.eval( test_modul, out )
end

"""
    snoopi_bench(config::BotConfig, expression::Expr, test_modul::Module = Main)

You can pass an expression directly. This is useful for simple experssions like `:(using MatLang)`.

However:

!!! warning
    Don't use this for complex expressions. The functionality isn't guaranteed. Especially if you
    - interpolate into it
    - use macros directly inside it
"""
function snoopi_bench(config::BotConfig, snoop_script::Expr, test_modul::Module  = Main)
    out = _snoopi_bench(config, snoop_script, test_modul)
    Core.eval( test_modul, out )
end

################################################################
"""
    @snoopi_bench botconfig::BotConfig, snoop_script::Expr


!!! warning
    This method isn't recommend. Use `@snoopi_bench(config::BotConfig, path_to_exmple_script::String)` instead.

# Examples
Benchmarking the load infer time
```julia
using SnoopCompile

println("loading infer benchmark")
@snoopi_bench BotConfig("MatLang") begin
 using MatLang
end
```

Benchmarking the example infer time
```julia
SnoopCompile

println("examples infer benchmark")
@snoopi_bench BotConfig("MatLang") begin
    using MatLang
    MatLang_rootpath = dirname(dirname(pathof("MatLang")))

    include("\$MatLang_rootpath/examples/Language_Fundamentals/usage_Matrices_and_Arrays.jl")
    include("\$MatLang_rootpath/examples/Language_Fundamentals/Data_Types/usage_Numeric_Types.jl")
end
```
"""
macro snoopi_bench(configExpr, snoop_script)
    @warn "This method isn't recommend. Use `@snoopi_bench(config::BotConfig, path_to_exmple_script::String)` instead."

    config = eval(configExpr)
    out = _snoopi_bench(config, snoop_script, __module__)
    return out
end

macro snoopi_bench(package_name::AbstractString, snoop_script)
    @warn "This method isn't recommend. Use `@snoopi_bench(config::BotConfig, path_to_exmple_script::String)` instead."

    f, l = __source__.file, __source__.line
    @warn "Replace `\"$package_name\"` with `BotConfig(\"$package_name\")`. That syntax will be deprecated in future versions. \n Happens at $f:$l"

    config = BotConfig(package_name)

    out = _snoopi_bench(config, snoop_script, __module__)
    return out
end

"""
    @snoopi_bench config::BotConfig

!!! warning
    This macro isn't recommend. Use the function form instead: `snoopi_bench(config::BotConfig)`.

Benchmarking the infer time of the tests:
```julia
@snoopi_bench BotConfig("MatLang")
```
"""
macro snoopi_bench(configExpr)
    @warn "This macro isn't recommend. Use the function form instead: `snoopi_bench(config::BotConfig)`."

    config = eval(configExpr)
    out = _snoopi_bench(config, __module__)
    return out
end

macro snoopi_bench(package_name::AbstractString)
    @warn "This macro isn't recommend. Use the function form instead: `snoopi_bench(config::BotConfig)`."

    f, l = __source__.file, __source__.line
    @warn "Replace `\"$package_name\"` with `BotConfig(\"$package_name\")`. That syntax will be deprecated in future versions. \n Happens at $f:$l"

    config = BotConfig(package_name)

    out = _snoopi_bench(config, __module__)
    return out
end
