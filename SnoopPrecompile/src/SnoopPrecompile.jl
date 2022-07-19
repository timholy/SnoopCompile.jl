module SnoopPrecompile

export @precompile_calls

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
    @precompile_calls f(args...)

    @precompile_calls :setup begin
        vars = ...
        @precompile_calls begin
            y = f(vars...)
            g(y)
        end
    end

`precompile` any method-calls that occur inside the expression. All calls (direct or indirect) inside an
"ordinary" `@precompile_calls` block (or one annotated with `:all`) will be precompiled. Code in `:setup`
blocks is not necessarily precompiled, and can be used to set up data for use in the calls you do want
to precompile.

`@precompile_calls` has three key features:

1. code inside (whether `:setup` or not) runs only when the package is being precompiled (i.e., a `*.ji`
   precompile cache file is being written)
2. in a non-`:setup` block the interpreter is disabled, ensuring your calls will be compiled
3. both direct and indirect callees will be precompiled, even for methods defined in other packages
   and even for runtime-dispatched callees (requires Julia 1.8 and above).
"""
macro precompile_calls(args...)
    local sym, ex
    if length(args) == 2
        # This is tagged with a Symbol
        isa(args[1], Symbol) || isa(args[1], QuoteNode) || throw(ArgumentError("expected a Symbol as the first argument to @precompile_calls, got $(typeof(args[1]))"))
        isa(args[2], Expr) || throw(ArgumentError("expected an expression as the second argument to @precompile_calls, got $(typeof(args[2]))"))
        sym = isa(args[1], Symbol) ? args[1]::Symbol : (args[1]::QuoteNode).value::Symbol
        sym ∈ (:setup, :all) || throw(ArgumentError("first argument to @precompile_calls must be :setup or :all, got $(QuoteNode(sym))"))
        ex = args[2]::Expr
    else
        length(args) == 1 || throw(ArgumentError("@precompile_calls accepts only one or two arguments"))
        isa(args[1], Expr) || throw(ArgumentError("@precompile_calls expected an expression, got $(typeof(args[1]))"))
        sym = :all
        ex = args[1]::Expr
    end
    if sym == :all
        if have_inference_tracking
            ex = quote
                Core.Compiler.Timings.reset_timings()
                Core.Compiler.__set_measure_typeinf(true)
                try
                    $ex
                catch err
                    @warn "error in executing `@precompile_calls` expression" exception=(err,catch_backtrace())
                finally
                    Core.Compiler.__set_measure_typeinf(false)
                    Core.Compiler.Timings.close_current_timer()
                end
                SnoopPrecompile.precompile_roots(Core.Compiler.Timings._timings[1].children)
            end
        end
        if have_force_compile
            ex = quote
                begin
                    Base.Experimental.@force_compile
                    $ex
                end
            end
        else
            # Use the hack on earlier Julia versions that blocks the interpreter
            pushfirst!(ex.args, :(while false end))
        end
    end
    return esc(quote
        # let
            if ccall(:jl_generating_output, Cint, ()) == 1 || SnoopPrecompile.verbose[]
                $ex
            end
        # end
    end)
end

end
