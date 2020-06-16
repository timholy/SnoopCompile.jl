export  @snoopi_bot, @snoopi_bench

"""
    @snoopi_bot config::BotConfig  snoop_script::Expr
    @snoopi_bot config::BotConfig

!!! warning
    This macro isn't recommend. Use the function form instead: `snoopi_bot(config::BotConfig, path_to_example_script::String)`.

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
    Base.depwarn("This macro isn't recommend. Use the function form instead: `snoopi_bot(config::BotConfig, path_to_example_script::String)`.", Symbol("@snoopi_bot"))
    config = eval(configExpr)
    out = _snoopi_bot(config, snoop_script, __module__)
    return out
end

macro snoopi_bot(package_name::String, snoop_script::Expr)
    Base.depwarn("This macro isn't recommend. Use the function form instead: `snoopi_bot(config::BotConfig, path_to_example_script::String)`.", Symbol("@snoopi_bot"))

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
    Base.depwarn("This macro isn't recommend. Use the function form instead: `snoopi_bot(config::BotConfig)`.", Symbol("@snoopi_bot"))

    config = eval(configExpr)
    out = _snoopi_bot(config, __module__)
    return out
end

macro snoopi_bot(package_name::String)
    f, l = __source__.file, __source__.line
    Base.depwarn("This macro isn't recommend. Use the function form instead: `snoopi_bot(config::BotConfig)`.", Symbol("@snoopi_bot"))

    @warn "Replace `\"$package_name\"` with `BotConfig(\"$package_name\")`. That syntax will be deprecated in future versions. \n Happens at $f:$l"

    config = BotConfig(package_name)
    out = _snoopi_bot(config, __module__)
    return out
end

################################################################
################################################################
"""
    @snoopi_bench botconfig::BotConfig, snoop_script::Expr


!!! warning
    This method isn't recommend. Use `snoopi_bench(config::BotConfig, path_to_example_script::String)` instead.

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
    Base.depwarn("This method isn't recommend. Use `snoop_bench(config::BotConfig, path_to_example_script::String)` instead.", Symbol("@snoopi_bench"))

    config = eval(configExpr)
    out = _snoopi_bench_cmd(config, snoop_script, __module__)
    return out
end

macro snoopi_bench(package_name::AbstractString, snoop_script)
    Base.depwarn("This method isn't recommend. Use `snoop_bench(config::BotConfig, path_to_example_script::String)` instead.", Symbol("@snoopi_bench"))

    f, l = __source__.file, __source__.line
    @warn "Replace `\"$package_name\"` with `BotConfig(\"$package_name\")`. That syntax will be deprecated in future versions. \n Happens at $f:$l"

    config = BotConfig(package_name)

    out = _snoopi_bench_cmd(config, snoop_script, __module__)
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
    Base.depwarn("This macro isn't recommend. Use the function form instead: `snoop_bench(config::BotConfig)`.", Symbol("@snoopi_bench"))

    config = eval(configExpr)
    out = _snoopi_bench_cmd(config, __module__)
    return out
end

macro snoopi_bench(package_name::AbstractString)
    Base.depwarn("This macro isn't recommend. Use the function form instead: `snoop_bench(config::BotConfig)`.", Symbol("@snoopi_bench"))

    f, l = __source__.file, __source__.line
    @warn "Replace `\"$package_name\"` with `BotConfig(\"$package_name\")`. That syntax will be deprecated in future versions. \n Happens at $f:$l"

    config = BotConfig(package_name)

    out = _snoopi_bench_cmd(config, __module__)
    return out
end

################################################################
################################################################

# deprecation and backward compatiblity
macro snoopiBot(args...)
     f, l = __source__.file, __source__.line
     Base.depwarn("`@snoopiBot` at $f:$l and its replacement `@snoopi_bot` are deprecated.", Symbol("@snoopiBot"))
     return esc(:(@snoopi_bot($(args...))))
end
macro snoopiBench(args...)
    f, l = __source__.file, __source__.line
    Base.depwarn("`@snoopiBench` at $f:$l and its replacement `@snoopi_bench` are deprecated.", Symbol("@snoopiBench"))
    return esc(:(@snoopi_bench($(args...))))
end

################################################################
################################################################
# old deprecations
@eval @deprecate $(Symbol("@snoopiBot")) $(Symbol("@snoopi_bot"))
@eval @deprecate $(Symbol("@snoopiBench")) $(Symbol("@snoopi_bench"))
# new deprecations
@eval @deprecate $(Symbol("@snoopi_bot")) $(Symbol("snoopi_bot"))
@eval @deprecate $(Symbol("@snoopi_bench")) $(Symbol("snoopi_bench"))
