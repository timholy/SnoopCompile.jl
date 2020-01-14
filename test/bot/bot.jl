using SnoopCompile, Test, Suppressor

cd(@__DIR__)
@testset "bot" begin
    @testset "precompileInclude" begin
        @testset "precompile_pather" begin
            precompilePath, precompileFolder = precompile_pather("TestPackage")
            @test  precompilePath == "\"../deps/SnoopCompile/precompile/precompile_TestPackage.jl\""
            @test precompileFolder == "$(pwd())/deps/SnoopCompile/precompile/"
        end

        @testset "precompile_activator" begin
            Base.write("activated.jl", """
            include("../deps/SnoopCompile/precompile/precompile_TestPackage.jl")
            _precompile_()
            """)

            precompilePath, precompileFolder = precompile_pather("TestPackage")
            @test (@capture_out precompile_activator("activated.jl", precompilePath)) == "precompile is already activated\n"
        end

        @testset "precompile_deactivator" begin
            Base.write("deactivated.jl", """
            # include("../deps/SnoopCompile/precompile/precompile_TestPackage.jl")
            # _precompile_()
            """)

            precompilePath, precompileFolder = precompile_pather("TestPackage")
            @test (@capture_out precompile_deactivator("deactivated.jl", precompilePath)) == "precompile is already deactivated\n"
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
          include(joinpath(examplePath,"Language_Fundamentals", "usage_Matrices_and_Arrays.jl"))
          include(joinpath(examplePath,"Language_Fundamentals", "Data_Types", "usage_Numeric_Types.jl"))
        end
    end

    @testset "snoopiBench" begin
        using Pkg; Pkg.develop("MatLang")

        examplePath = Base.read(`cmd /c julia -e 'import MatLang; print(pathof(MatLang))'`, String)
        cd(dirname(dirname(examplePath)))

        @snoopiBench "MatLang" begin
            using MatLang
            examplePath = joinpath(dirname(dirname(pathof(MatLang))), "examples")
            include(joinpath(examplePath,"Language_Fundamentals", "usage_Matrices_and_Arrays.jl"))
            include(joinpath(examplePath,"Language_Fundamentals", "Data_Types", "usage_Numeric_Types.jl"))
        end
    end
    =#

end
