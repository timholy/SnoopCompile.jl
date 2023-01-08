module SnoopPrecompile

export @precompile_all_calls, @precompile_setup

@static if VERSION >= v"1.6"
    using Preferences
end

@static if VERSION >= v"1.6"
    const skip_precompile = @load_preference("skip_precompile", String[])
else
    const skip_precompile = String[]
end

const verbose = Ref(false)    # if true, prints all the precompiles
const have_inference_tracking = isdefined(Core.Compiler, :__set_measure_typeinf)
const have_force_compile = isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("#@force_compile"))

function precompile_roots(roots)
    @assert have_inference_tracking
    for child in roots
        mi = child.mi_info.mi
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
    string(__module__) in skip_precompile && return :()
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
            Core.Compiler.Timings.reset_timings()
            Core.Compiler.__set_measure_typeinf(true)
            try
                $ex
            finally
                Core.Compiler.__set_measure_typeinf(false)
                Core.Compiler.Timings.close_current_timer()
            end
            $SnoopPrecompile.precompile_roots(Core.Compiler.Timings._timings[1].children)
        end
    end
    return esc(quote
        if ccall(:jl_generating_output, Cint, ()) == 1 || $SnoopPrecompile.verbose[]
            $ex
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
    string(__module__) in skip_precompile && return :()
    return esc(quote
        # let
            if ccall(:jl_generating_output, Cint, ()) == 1 || $SnoopPrecompile.verbose[]
                $ex
            end
        # end
    end)
end

end
