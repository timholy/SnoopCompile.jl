using SnoopCompile, Test, Suppressor

cd(@__DIR__)
@testset "utilities" begin
    @testset "precompilePather" begin
        precompilePath, precompileFolder = precompilePather("TestPackage")
        @test  precompilePath == "\"../deps/SnoopCompile/precompile/precompile_TestPackage.jl\""
        @test precompileFolder == "$(pwd())/deps/SnoopCompile/precompile/"
    end

    @testset "precompileActivator" begin
        precompilePath, precompileFolder = precompilePather("TestPackage")
        @test (@capture_out precompileActivator("utilities/activated.jl", precompilePath)) == "precompile is already activated\n"
    end

    @testset "precompileDeactivator" begin
        precompilePath, precompileFolder = precompilePather("TestPackage")
        @test (@capture_out precompileDeactivator("utilities/deactivated.jl", precompilePath)) == "precompile is already deactivated\n"
    end
end
