module SnoopPrecompile

export @precompile_all_calls, @precompile_setup, @time_precompiled

const verbose = Ref(false)    # if true, prints all the precompiles
const have_inference_tracking = isdefined(Core.Compiler, :__set_measure_typeinf)
const have_force_compile = isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("#@force_compile"))

# Don't make these `MethodInstance(obj)` to avoid potential conflict with SnoopCompile itself
getmi(obj::Core.Compiler.Timings.Timing) = obj.mi_info.mi
getmi(obj::Core.CodeInstance) = obj.def
getmi(obj::Core.MethodInstance) = obj

function precompile_roots(roots)
    @assert have_inference_tracking
    for child in roots
        mi = getmi(child)
        precompile(mi.specTypes) # TODO: Julia should allow one to pass `mi` directly (would handle `invoke` properly)
        verbose[] && println(mi)
    end
end

"""
    @precompile_all_calls f(args...)

`precompile` any method-calls that occur inside the expression. All calls (direct or indirect) inside a
`@precompile_all_calls` block will be precompiled.

`@precompile_all_calls` has three key features:

1. code inside runs only when the package is being precompiled (i.e., a `*.ji`
   precompile cache file is being written)
2. the interpreter is disabled, ensuring your calls will be compiled
3. both direct and indirect callees will be precompiled, even for methods defined in other packages
   and even for runtime-dispatched callees (requires Julia 1.8 and above).

!!! note
    For comprehensive precompilation, ensure the first usage of a given method/argument-type combination
    occurs inside `@precompile_all_calls`.

    In detail: runtime-dispatched callees are captured only when type-inference is executed, and they
    are inferred only on first usage. Inferrable calls that trace back to a method defined in your package,
    and their *inferrable* callees, will be precompiled regardless of "ownership" of the callees
    (Julia 1.8 and higher).

    Consequently, this recommendation matters only for:

        - direct calls to methods defined in Base or other packages OR
        - indirect runtime-dispatched calls to such methods.
"""
macro precompile_all_calls(ex::Expr)
    if have_force_compile
        ex = quote
            begin
                Base.Experimental.@force_compile
                $ex
            end
        end
    else
        # Use the hack on earlier Julia versions that blocks the interpreter
        ex = quote
            while false end
            $ex
        end
    end
    if have_inference_tracking
        ex = quote
            thunk() = $ex
            Core.Compiler.Timings.reset_timings()
            Core.Compiler.__set_measure_typeinf(true)
            try
                Base.invokelatest(thunk)
            finally
                Core.Compiler.__set_measure_typeinf(false)
                Core.Compiler.Timings.close_current_timer()
            end
            $SnoopPrecompile.precompile_roots(Core.Compiler.Timings._timings[1].children)
        end
    end
    return esc(quote
        if ccall(:jl_generating_output, Cint, ()) == 1 || $SnoopPrecompile.verbose[]
            let
                $ex
            end
        end
    end)
end

"""
    @precompile_setup begin
        vars = ...
        ⋮
    end

Run the code block only during package precompilation. `@precompile_setup` is often used in combination
with [`@precompile_all_calls`](@ref), for example:

    @precompile_setup begin
        vars = ...
        @precompile_all_calls begin
            y = f(vars...)
            g(y)
            ⋮
        end
    end

`@precompile_setup` does not force compilation (though it may happen anyway) nor intentionally capture
runtime dispatches (though they will be precompiled anyway if the runtime-callee is for a method belonging
to your package).
"""
macro precompile_setup(ex::Expr)
    return esc(quote
        let
            if ccall(:jl_generating_output, Cint, ()) == 1 || $SnoopPrecompile.verbose[]
                $ex
            end
        end
    end)
end

"""
    @time_precompiled expr
    @time_precompiled recordmacro expr

Measure the time required to execute a precompilation workload `expr`. This is typically used in a fresh Julia session
immediately after loading a package, to determine the impact of precompilation on the first execution of the entire workload.

The measured time is for the workload in [`@precompile_all_calls`](@ref); time needed to run the code in [`@precompile_setup`](@ref)
is not included. Having a `@precompile_setup` is not required (your workload can just use `@precompile_all_calls`),
but if your package uses `@precompile_setup` you should include it in `expr`.

Optionally, you can supply a different `recordmacro` operation than `@time`. As with `@time`, `recordmacro` is applied only to
the workload in `@precompile_all_calls`.

# Examples

```
julia> using SnoopPrecompile, MyCoolPackage

julia> @time_precompiled @precompile_setup begin
            vars = ...
            @precompile_all_calls begin
                y = f(vars...)
                g(y)
                ⋮
            end
        end
```
The expresssion inside `@time_precompiled` was copied from the precompile workload used in `MyCoolPackage`.

If you want to see what's being inferred, then supply `@snoopi_deep` as the first argument:

```
julia> using SnoopPrecompile, SnoopCompileCore, MyCoolPackage

julia> tinf = @time_precompiled @snoopi_deep @precompile_setup begin ... end;

julia> using SnoopCompile
```

and then perform analysis on `tinf`.

A fresh session is required for each analysis.
"""
macro time_precompiled(ex::Expr)
    cmd = Symbol("@time")
    if ex.head == :macrocall
        sym = macrosym(ex)
        if sym ∉ (Symbol("@precompile_setup"), Symbol("@precompile_all_calls"))
            cmd = sym
            ex = ex.args[end]::Expr
        end
    end
    ex = replace_macros!(copy(ex), cmd)
    return esc(ex)
end

function replace_macros!(@nospecialize(ex), cmd)
    if ex isa Expr
        head = ex.head
        if head === :macrocall
            arg1 = macrosym(ex)
            if arg1 == Symbol("@precompile_setup")
                ex.head = :let
                deleteat!(ex.args, 1:length(ex.args)-1)
                pushfirst!(ex.args, Expr(:block))
            elseif arg1 == Symbol("@precompile_all_calls")
                workload = ex.args[end]
                empty!(ex.args)
                ex.head = :block
                push!(ex.args, :(thunk() = $workload))
                push!(ex.args, Expr(:macrocall, cmd, LineNumberNode(@__LINE__, @__FILE__), :(Base.invokelatest(thunk))))
            end
        end
        for arg in ex.args
            replace_macros!(arg, cmd)
        end
    elseif ex isa QuoteNode
        replace_macros!(ex.value, cmd)
    end
    return ex
end

function macrosym(ex::Expr)
    arg1 = ex.args[1]
    if arg1 isa Expr
        arg1 = (arg1.args[2]::QuoteNode).value
    end
    return arg1::Symbol
end

end
