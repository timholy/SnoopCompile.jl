function snoopi_bot(modul::Module, config::BotConfig, snoop_script)

    package_name = config.package_name
    blacklist = config.blacklist
    subst = config.subst
    os = config.os
    else_os = config.else_os
    version = config.version
    else_version = config.else_version
    precompiles_rootpath = config.precompiles_rootpath
    ################################################################
    package_path = pathof_noload(package_name)
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
        precompile_deactivator($package_path);
        ################################################################

        ### Log the compiles
        # data = Core.eval($modul, SnoopCompile.snoopi($(Meta.quot(snoop_script))))
        # TODO use code directly for now
        empty!(__inf_timing__)
        start_timing()
        try
            $snoop_script
        finally
            stop_timing()
        end
        data = sort_timed_inf($tmin)

        ################################################################
        ### Parse the compiles and generate precompilation scripts
        pc = SnoopCompile.parcel(data, subst = $subst, blacklist = $blacklist)
        if !haskey(pc, packageSym)
            @error "no precompile signature is found for $package_name. Don't load the package before snooping. Restart your Julia session."
        end
        onlypackage = Dict( packageSym => sort(pc[packageSym]) )
        SnoopCompile.write($precompile_folder, onlypackage)
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
  MatLang_rootpath = dirname(dirname(pathof("MatLang")))

  include("\$MatLang_rootpath/examples/Language_Fundamentals/usage_Matrices_and_Arrays.jl")
  include("\$MatLang_rootpath/examples/Language_Fundamentals/Data_Types/usage_Numeric_Types.jl")
end
```
"""
macro snoopi_bot(configExpr, snoop_script)
    config = eval(configExpr)
    out = snoopi_bot(__module__, config, snoop_script)
    return out
end

macro snoopi_bot(package_name::String, snoop_script)
    f, l = __source__.file, __source__.line
    @warn "Replace `\"$package_name\"` with `BotConfig(\"$package_name\")`. That syntax will be deprecated in future versions. \n Happens at $f:$l"

    config = BotConfig(package_name)

    out = snoopi_bot(__module__, config, snoop_script)
    return out
end

################################################################

function snoopi_bot(modul, config::BotConfig)

    package_name = config.package_name
    package_rootpath = dirname(dirname(pathof_noload(package_name)))
    runtestpath = "$package_rootpath/test/runtests.jl"

    package = Symbol(package_name)
    snoop_script = quote
        using $(package)
        include($runtestpath)
    end
    out = snoopi_bot(modul, config, snoop_script)
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
    out = snoopi_bot(__module__, config)
    return out
end

macro snoopi_bot(package_name::String)
    f, l = __source__.file, __source__.line
    @warn "Replace `\"$package_name\"` with `BotConfig(\"$package_name\")`. That syntax will be deprecated in future versions. \n Happens at $f:$l"

    config = BotConfig(package_name)

    out = snoopi_bot(__module__, config)
    return out
end
