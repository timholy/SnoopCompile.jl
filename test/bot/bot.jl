using SnoopCompile, Test

stripall(x::String) = replace(x, r"\s|\n"=>"")

cd(@__DIR__)
@testset "bot" begin
    @testset "precompile_include - single os" begin
        package_name = "TestPackage"
        package_path = joinpath(pwd(),"$package_name.jl","src","$package_name.jl")
        includer_path = joinpath(dirname(package_path), "precompile_includer.jl")

        SnoopCompile.new_includer_file(package_name, package_path, nothing, nothing, nothing, nothing)
        SnoopCompile.add_includer(package_name, package_path)

        @test occursin("include(\"precompile_includer.jl\")", stripall(Base.read(package_path, String)))

        SnoopCompile.precompile_deactivator(package_path)
        @test occursin("should_precompile=false", stripall(Base.read(includer_path, String)))

        SnoopCompile.precompile_activator(package_path)
        includer_text = stripall(Base.read(includer_path, String))
        @test occursin("should_precompile=true", includer_text)

        @test occursin("ismultios=false", includer_text)

        @test occursin(stripall("""elseif !ismultios
            include("../deps/SnoopCompile/precompile/precompile_$package_name.jl")
            _precompile_()
        """), includer_text)
    end

    @testset "precompile_include - multi os" begin
        package_name = "TestPackage2"
        package_path = joinpath(pwd(),"$package_name.jl","src","$package_name.jl")
        includer_path = joinpath(dirname(package_path), "precompile_includer.jl")

        SnoopCompile.new_includer_file(package_name, package_path, ["linux", "windows"], nothing, nothing, nothing)
        SnoopCompile.add_includer(package_name, package_path)

        @test occursin("include(\"precompile_includer.jl\")", stripall(Base.read(package_path, String)))

        SnoopCompile.precompile_deactivator(package_path)
        @test occursin("should_precompile=false", stripall(Base.read(includer_path, String)))

        SnoopCompile.precompile_activator(package_path)
        includer_text = stripall(Base.read(includer_path, String))

        @test occursin("should_precompile=true", includer_text)

        @test occursin("ismultios=true", includer_text)

        @test occursin(stripall("""elseif !ismultios
            include("../deps/SnoopCompile/precompile/precompile_$package_name.jl")
            _precompile_()
        """), includer_text)

        @test occursin(stripall("""elseif Sys.iswindows()
            include("../deps/SnoopCompile/precompile/windows/precompile_$package_name.jl")
            _precompile_()
        """), includer_text)

        @test occursin(stripall("""elseif Sys.islinux()
            include("../deps/SnoopCompile/precompile/linux/precompile_$package_name.jl")
            _precompile_()
        """), includer_text)
    end

    using Pkg;
    package_name = "TestPackage"
    package_path = joinpath(pwd(),"$package_name.jl")
    Pkg.develop(PackageSpec(path=package_path))

    package_name2 = "TestPackage2"
    package_path2 = joinpath(pwd(),"$package_name2.jl")
    Pkg.develop(PackageSpec(path=package_path2))

    if VERSION >=  v"1.2"
        @testset "snoopi_bot" begin
            cd(package_path)

            include("TestPackage.jl/deps/SnoopCompile/snoopi_bot.jl")

            @test isfile("deps/SnoopCompile/precompile/precompile_TestPackage.jl")

            precompile_text = Base.read("deps/SnoopCompile/precompile/precompile_TestPackage.jl", String)

            @test occursin("hello", precompile_text)
            @test occursin("domath", precompile_text)
        end

        @testset "snoopi_bench" begin
            cd(package_path)

            include("TestPackage.jl/deps/SnoopCompile/snoopi_bench.jl")
        end

        @testset "snoopi_bot_multios" begin
            cd(package_path2)

            os, osfun = SnoopCompile.detectOS()

            include("TestPackage2.jl/deps/SnoopCompile/snoopi_bot_multios.jl")

            @test isfile("deps/SnoopCompile/precompile/$os/precompile_TestPackage2.jl")

            precompile_text = Base.read("deps/SnoopCompile/precompile/$os/precompile_TestPackage2.jl", String)

            if os == "windows"
                @test occursin("hello2", precompile_text)
                @test !occursin("domath2", precompile_text)
            else
                @test !occursin("hello2", precompile_text)
                @test occursin("domath2", precompile_text)
            end
        end

        @testset "snoopi_bench-multios" begin
            cd(package_path2)

            include("TestPackage2.jl/deps/SnoopCompile/snoopi_bench.jl")
        end

        # workflow.yml file is tested online:
        # https://github.com/aminya/Example.jl/actions
    end
end
