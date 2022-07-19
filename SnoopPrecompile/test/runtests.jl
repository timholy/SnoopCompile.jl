using SnoopPrecompile
using Test

@testset "SnoopPrecompile.jl" begin
    push!(LOAD_PATH, @__DIR__)
    using SnoopPC_A
    if Base.VERSION >= v"1.8.0-rc1"
        # Check that calls inside :setup are not precompiled
        m = which(Tuple{typeof(Base.vect), Vararg{T}} where T)
        have_mytype = false
        for mi in m.specializations
            mi === nothing && continue
            have_mytype |= Base.unwrap_unionall(mi.specTypes).parameters[2] === SnoopPC_A.MyType
        end
        @test !have_mytype
        # Check that calls inside @precompile_calls are precompiled
        m = only(methods(SnoopPC_A.call_findfirst))
        count = 0
        for mi in m.specializations
            mi === nothing && continue
            sig = Base.unwrap_unionall(mi.specTypes)
            @test sig.parameters[2] == SnoopPC_A.MyType
            @test sig.parameters[3] == Vector{SnoopPC_A.MyType}
            count += 1
        end
        @test count == 1
        # Even one that was runtime-dispatched
        m = which(Tuple{typeof(findfirst), Base.Fix2{typeof(==), T}, Vector{T}} where T)
        count = 0
        for mi in m.specializations
            mi === nothing && continue
            sig = Base.unwrap_unionall(mi.specTypes)
            if sig.parameters[3] == Vector{SnoopPC_A.MyType}
                count += 1
            end
        end
        @test count == 1
    end
end
