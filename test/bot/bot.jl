using SnoopCompile, Test, Suppressor

cd(@__DIR__)
@testset "bot" begin
    @testset "precompilePather" begin
        precompilePath, precompileFolder = precompilePather("TestPackage")
        @test  precompilePath == "\"../deps/SnoopCompile/precompile/precompile_TestPackage.jl\""
        @test precompileFolder == "$(pwd())/deps/SnoopCompile/precompile/"
    end

    @testset "precompileActivator" begin
        precompilePath, precompileFolder = precompilePather("TestPackage")
        @test (@capture_out precompileActivator("activated.jl", precompilePath)) == "precompile is already activated\n"
    end

    @testset "precompileDeactivator" begin
        precompilePath, precompileFolder = precompilePather("TestPackage")
        @test (@capture_out precompileDeactivator("deactivated.jl", precompilePath)) == "precompile is already deactivated\n"
    end

    # fails because Main.Example is filtered out
    # instead test the code in MatLang actions: https://github.com/juliamatlab/MatLang/actions?query=workflow%3ASnoopCompile
    #=
    @testset "snoopiBot" begin
        @snoopiBot "Example" begin
          include("src/Example.jl")
          using Main.Example
          hello("Julia")
          domath(2.0)
          domath(2)
          domath.([2.0 2 Float32(1)])
        end
    end

    @testset "snoopiBenchBot" begin
        @snoopiBenchBot "Example" begin
          include("src/Example.jl")
          using Main.Example
          hello("Julia")
          domath(2.0)
          domath(2)
          domath.([2.0 2 Float32(1)])
        end
    end
    =#
end
