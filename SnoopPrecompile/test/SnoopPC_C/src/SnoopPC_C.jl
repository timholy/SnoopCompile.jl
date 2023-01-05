module SnoopPC_C

using SnoopPrecompile

# mimic `RecipesBase` code - see github.com/JuliaPlots/Plots.jl/issues/4597 and #317
module RB
    export @recipe

    apply_recipe(args...) = nothing
    macro recipe(ex::Expr)
        _, func_body = ex.args
        func = Expr(:call, :($RB.apply_recipe))
        Expr(
            :function,
            func,
            quote
                @nospecialize
                func_return = $func_body
            end |> esc
        )
    end
end
using .RB

@precompile_setup begin
    struct Foo end
    @precompile_all_calls begin
        @recipe f(::Foo) = nothing
    end
end

end # module SnoopPC_C
