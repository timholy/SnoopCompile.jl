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
                finally
                    Core.Compiler.__set_measure_typeinf(false)
                    Core.Compiler.Timings.close_current_timer()
                end
                SnoopPrecompile.precompile_roots(Core.Compiler.Timings._timings[1].children)
            end
        elseif have_force_compile
            ex = quote
                begin
                    Base.Experimental.@force_compile
                    $ex
                end
            end
        end
    end
    ex = quote
        if ccall(:jl_generating_output, Cint, ()) == 1 || SnoopPrecompile.verbose[]
            $ex
        end
    end
    return esc(ex)
end

end
