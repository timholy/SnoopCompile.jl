module SnoopPC_A

using SnoopPrecompile: @precompile_setup, @precompile_all_calls

struct MyType
    x::Int
end

if isdefined(Base, :inferencebarrier)
    inferencebarrier(@nospecialize(arg)) = Base.inferencebarrier(arg)
else
    inferencebarrier(@nospecialize(arg)) = Ref{Any}(arg)[]
end

function call_findfirst(x, list)
    # call a method defined in Base by runtime dispatch
    return findfirst(==(inferencebarrier(x)), inferencebarrier(list))
end

let
    @precompile_setup begin
        list = [MyType(1), MyType(2), MyType(3)]
        @precompile_all_calls begin
            call_findfirst(MyType(2), list)
        end
    end
end

end # module SnoopPC_A
