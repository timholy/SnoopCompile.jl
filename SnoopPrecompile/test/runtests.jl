using SnoopPrecompile
using Test
using UUIDs

@testset "SnoopPrecompile.jl" begin
    push!(LOAD_PATH, @__DIR__)

    using SnoopPC_A
    if VERSION >= v"1.8.0-rc1"
        # Check that calls inside :setup are not precompiled
        m = which(Tuple{typeof(Base.vect), Vararg{T}} where T)
        have_mytype = false
        for mi in m.specializations
            mi === nothing && continue
            have_mytype |= Base.unwrap_unionall(mi.specTypes).parameters[2] === SnoopPC_A.MyType
        end
        have_mytype && @warn "Code in setup block was precompiled"
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

    if VERSION >= v"1.7"   # so we can use redirect_stderr(f, ::Pipe)
        pipe = Pipe()
        id = Base.PkgId(UUID("d38b61e7-59a2-4ef9-b4d3-320bdc69b817"), "SnoopPC_B")
        redirect_stderr(pipe) do
            @test_throws Exception Base.require(id)
        end
        close(pipe.in)
        str = read(pipe.out, String)
        @test occursin(r"UndefVarError: `?missing_function`? not defined", str)
    end

    if VERSION >= v"1.6"
        using SnoopPC_C
    end

    if VERSION >= v"1.6"
        script = """
        push!(LOAD_PATH, @__DIR__)
        using SnoopPC_D
        exit(isdefined(SnoopPC_D, :workload_ran) === parse(Bool, ARGS[1]) ? 0 : 1)
        """

        SnoopPrecompile.Preferences.set_preferences!(SnoopPrecompile, "skip_precompile" => ["SnoopPC_D"])
        @test success(run(`$(Base.julia_cmd()) --project=$(Base.active_project()) -e $script 0`))

        SnoopPrecompile.Preferences.delete_preferences!(SnoopPrecompile, "skip_precompile"; force = true)
        @test success(run(`$(Base.julia_cmd()) --project=$(Base.active_project()) -e $script 1`))
    end
end
