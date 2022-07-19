module SnoopPC_A

using SnoopPrecompile

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
    @precompile_calls :setup begin
        list = [MyType(1), MyType(2), MyType(3)]
    end
    @precompile_calls begin
        call_findfirst(MyType(2), list)
    end
end

end # module SnoopPC_A
