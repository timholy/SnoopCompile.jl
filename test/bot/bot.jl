using SnoopCompile, Test, Suppressor

cd(@__DIR__)
@testset "bot" begin
    @testset "precompileInclude" begin
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
    end


    # Fails. # snoopiBot pwd() differs from what it is cd to
    # instead test the code in MatLang actions: https://github.com/juliamatlab/MatLang/actions?query=workflow%3ASnoopCompile
    #=
    @testset "snoopiBot" begin
        using Pkg; Pkg.develop("MatLang")

        examplePath = Base.read(`cmd /c julia -e 'import MatLang; print(pathof(MatLang))'`, String)
        cd(dirname(dirname(examplePath)))

        @snoopiBot "MatLang" begin

          using MatLang
          examplePath = joinpath(dirname(dirname(pathof(MatLang))), "examples")
          # include(joinpath(examplePath,"Language_Fundamentals", "usage_Entering_Commands.jl"))
          include(joinpath(examplePath,"Language_Fundamentals", "usage_Matrices_and_Arrays.jl"))
          include(joinpath(examplePath,"Language_Fundamentals", "Data_Types", "usage_Numeric_Types.jl"))
        end
    end

    @testset "snoopiBenchBot" begin
        using Pkg; Pkg.develop("MatLang")

        examplePath = Base.read(`cmd /c julia -e 'import MatLang; print(pathof(MatLang))'`, String)
        cd(dirname(dirname(examplePath)))

        @snoopiBenchBot "MatLang" begin
            using MatLang
            examplePath = joinpath(dirname(dirname(pathof(MatLang))), "examples")
            # include(joinpath(examplePath,"Language_Fundamentals", "usage_Entering_Commands.jl"))
            include(joinpath(examplePath,"Language_Fundamentals", "usage_Matrices_and_Arrays.jl"))
            include(joinpath(examplePath,"Language_Fundamentals", "Data_Types", "usage_Numeric_Types.jl"))
        end
    end
    =#

end
