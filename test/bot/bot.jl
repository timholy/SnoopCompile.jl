using SnoopCompile, Test

stripall(x::String) = replace(x, r"\s|\n"=>"")

cd(@__DIR__)

@testset "bot" begin
    @testset "add_includer" begin
        package_name = "TestPackage"
        package_path = joinpath(pwd(),"$package_name.jl","src","$package_name.jl")
        includer_path = joinpath(dirname(package_path), "precompile_includer.jl")

        SnoopCompile.add_includer(package_name, package_path)

        @test occursin("include(\"precompile_includer.jl\")", stripall(Base.read(package_path, String)))
    end

    @testset "precompile de/activation" begin
        package_name = "TestPackage"
        package_path = joinpath(pwd(),"$package_name.jl","src","$package_name.jl")
        precompiles_rootpath = joinpath(pwd(),"$package_name.jl","deps/SnoopCompile/precompile")
        includer_path = joinpath(dirname(package_path), "precompile_includer.jl")

        SnoopCompile.new_includer_file(package_name, package_path, precompiles_rootpath, nothing, nothing, nothing, nothing)

        SnoopCompile.precompile_deactivator(package_path)
        @test occursin("should_precompile=false", stripall(Base.read(includer_path, String)))

        SnoopCompile.precompile_activator(package_path)
        includer_text = stripall(Base.read(includer_path, String))
        @test occursin("should_precompile=true", includer_text)
    end

    @testset "precompile new_includer_file" begin
        package_name = "TestPackage"
        package_path = joinpath(pwd(),"$package_name.jl","src","$package_name.jl")
        precompiles_rootpath = joinpath(pwd(),"$package_name.jl","deps/SnoopCompile/precompile")
        includer_path = joinpath(dirname(package_path), "precompile_includer.jl")


        @testset "no os, no else_os, no version, no else_version" begin
            SnoopCompile.new_includer_file(package_name, package_path, precompiles_rootpath, nothing, nothing, nothing, nothing)
            includer_text = stripall(Base.read(includer_path, String))
            @test occursin("ismultios=false", includer_text)
            @test occursin("ismultiversion=false", includer_text)

            @test occursin(stripall("""
            @static if !should_precompile
                # nothing
            elseif !ismultios && !ismultiversion
                include("../deps/SnoopCompile/precompile/precompile_TestPackage.jl")
                _precompile_()
            else

            end
            """), includer_text)
        end

        @testset "yes os, no else_os, no version, no else_version" begin
            SnoopCompile.new_includer_file(package_name, package_path, precompiles_rootpath, ["linux", "windows"], nothing, nothing, nothing)
            includer_text = stripall(Base.read(includer_path, String))
            @test occursin("ismultios=true", includer_text)
            @test occursin("ismultiversion=false", includer_text)

            @test occursin(stripall("""
            @static if !should_precompile
                # nothing
            elseif !ismultios && !ismultiversion
                include("../deps/SnoopCompile/precompile/precompile_TestPackage.jl")
                _precompile_()
            else
                @static if Sys.islinux()
                    include("../deps/SnoopCompile/precompile/linux/precompile_TestPackage.jl")
                    _precompile_()
                elseif Sys.iswindows()
                    include("../deps/SnoopCompile/precompile/windows/precompile_TestPackage.jl")
                    _precompile_()
                else
                end

            end
            """), includer_text)
        end

        @testset "yes os, yes else_os, no version, no else_version" begin
            SnoopCompile.new_includer_file(package_name, package_path, precompiles_rootpath, ["linux", "windows"], "linux", nothing, nothing)
            includer_text = stripall(Base.read(includer_path, String))
            @test occursin("ismultios=true", includer_text)
            @test occursin("ismultiversion=false", includer_text)

            @test occursin(stripall("""
            @static if !should_precompile
                # nothing
            elseif !ismultios && !ismultiversion
                include("../deps/SnoopCompile/precompile/precompile_TestPackage.jl")
                _precompile_()
            else
                @static if Sys.islinux()
                    include("../deps/SnoopCompile/precompile/linux/precompile_TestPackage.jl")
                    _precompile_()
                elseif Sys.iswindows()
                    include("../deps/SnoopCompile/precompile/windows/precompile_TestPackage.jl")
                    _precompile_()
                else
                    include("../deps/SnoopCompile/precompile/linux/precompile_TestPackage.jl")
                    _precompile_()
                end

            end
            """), includer_text)
        end

        @testset "no os, no else_os, yes version, no else_version" begin
            SnoopCompile.new_includer_file(package_name, package_path, precompiles_rootpath, nothing, nothing, [v"1.0", v"1.4.1"], nothing)
            includer_text = stripall(Base.read(includer_path, String))
            @test occursin("ismultios=false", includer_text)
            @test occursin("ismultiversion=true", includer_text)

            @test occursin(stripall("""
            @static if !should_precompile
                # nothing
            elseif !ismultios && !ismultiversion
                include("../deps/SnoopCompile/precompile/precompile_TestPackage.jl")
                _precompile_()
            else
                @static if VERSION <= v"1.0.0"
                    include("../deps/SnoopCompile/precompile//1.0.0/precompile_TestPackage.jl")
                    _precompile_()
                elseif VERSION <= v"1.4.1"
                    include("../deps/SnoopCompile/precompile//1.4.1/precompile_TestPackage.jl")
                    _precompile_()
                else
                end

            end
            """), includer_text)
        end


        @testset "no os, no else_os, yes version, yes else_version" begin
            SnoopCompile.new_includer_file(package_name, package_path, precompiles_rootpath, nothing, nothing, [v"1.0", v"1.4.1"], v"1.4.1")
            includer_text = stripall(Base.read(includer_path, String))
            @test occursin("ismultios=false", includer_text)
            @test occursin("ismultiversion=true", includer_text)

            @test occursin(stripall("""
            @static if !should_precompile
                # nothing
            elseif !ismultios && !ismultiversion
                include("../deps/SnoopCompile/precompile/precompile_TestPackage.jl")
                _precompile_()
            else
                @static if VERSION <= v"1.0.0"
                    include("../deps/SnoopCompile/precompile//1.0.0/precompile_TestPackage.jl")
                    _precompile_()
                elseif VERSION <= v"1.4.1"
                    include("../deps/SnoopCompile/precompile//1.4.1/precompile_TestPackage.jl")
                    _precompile_()
                else
                    include("../deps/SnoopCompile/precompile//1.4.1/precompile_TestPackage.jl")
                    _precompile_()
                end

            end
            """), includer_text)
        end

        @testset "yes os, yes else_os, yes version, no else_version" begin
            SnoopCompile.new_includer_file(package_name, package_path, precompiles_rootpath, ["linux", "windows"], "linux", [v"1.0", v"1.4.1"], nothing)
            includer_text = stripall(Base.read(includer_path, String))
            @test occursin("ismultios=true", includer_text)
            @test occursin("ismultiversion=true", includer_text)

            @test occursin(stripall("""
            @static if !should_precompile
                # nothing
            elseif !ismultios && !ismultiversion
                include("../deps/SnoopCompile/precompile/precompile_TestPackage.jl")
                _precompile_()
            else
                @static if Sys.islinux()
                    @static if VERSION <= v"1.0.0"
                        include("../deps/SnoopCompile/precompile/linux/1.0.0/precompile_TestPackage.jl")
                        _precompile_()
                    elseif VERSION <= v"1.4.1"
                        include("../deps/SnoopCompile/precompile/linux/1.4.1/precompile_TestPackage.jl")
                        _precompile_()
                    else
                    end

                elseif Sys.iswindows()
                    @static if VERSION <= v"1.0.0"
                        include("../deps/SnoopCompile/precompile/windows/1.0.0/precompile_TestPackage.jl")
                        _precompile_()
                    elseif VERSION <= v"1.4.1"
                        include("../deps/SnoopCompile/precompile/windows/1.4.1/precompile_TestPackage.jl")
                        _precompile_()
                    else
                    end

                else
                    @static if VERSION <= v"1.0.0"
                        include("../deps/SnoopCompile/precompile/linux/1.0.0/precompile_TestPackage.jl")
                        _precompile_()
                    elseif VERSION <= v"1.4.1"
                        include("../deps/SnoopCompile/precompile/linux/1.4.1/precompile_TestPackage.jl")
                        _precompile_()
                    else
                    end

                end

            end
            """), includer_text)
        end

        @testset "yes os, yes else_os, yes version, yes else_version" begin
            SnoopCompile.new_includer_file(package_name, package_path, precompiles_rootpath, ["linux", "windows"], "linux", [v"1.0", v"1.4.1"], v"1.4.1")
            includer_text = stripall(Base.read(includer_path, String))
            @test occursin("ismultios=true", includer_text)
            @test occursin("ismultiversion=true", includer_text)

            @test occursin(stripall("""
            @static if !should_precompile
                # nothing
            elseif !ismultios && !ismultiversion
                include("../deps/SnoopCompile/precompile/precompile_TestPackage.jl")
                _precompile_()
            else
                @static if Sys.islinux()
                    @static if VERSION <= v"1.0.0"
                        include("../deps/SnoopCompile/precompile/linux/1.0.0/precompile_TestPackage.jl")
                        _precompile_()
                    elseif VERSION <= v"1.4.1"
                        include("../deps/SnoopCompile/precompile/linux/1.4.1/precompile_TestPackage.jl")
                        _precompile_()
                    else
                        include("../deps/SnoopCompile/precompile/linux/1.4.1/precompile_TestPackage.jl")
                        _precompile_()
                    end

                elseif Sys.iswindows()
                    @static if VERSION <= v"1.0.0"
                        include("../deps/SnoopCompile/precompile/windows/1.0.0/precompile_TestPackage.jl")
                        _precompile_()
                    elseif VERSION <= v"1.4.1"
                        include("../deps/SnoopCompile/precompile/windows/1.4.1/precompile_TestPackage.jl")
                        _precompile_()
                    else
                        include("../deps/SnoopCompile/precompile/windows/1.4.1/precompile_TestPackage.jl")
                        _precompile_()
                    end

                else
                    @static if VERSION <= v"1.0.0"
                        include("../deps/SnoopCompile/precompile/linux/1.0.0/precompile_TestPackage.jl")
                        _precompile_()
                    elseif VERSION <= v"1.4.1"
                        include("../deps/SnoopCompile/precompile/linux/1.4.1/precompile_TestPackage.jl")
                        _precompile_()
                    else
                        include("../deps/SnoopCompile/precompile/linux/1.4.1/precompile_TestPackage.jl")
                        _precompile_()
                    end

                end

            end
            """), includer_text)
        end

        @testset "yes os, no else_os, yes version, no else_version" begin
            SnoopCompile.new_includer_file(package_name, package_path, precompiles_rootpath, ["linux", "windows"], nothing, [v"1.0", v"1.4.1"], nothing)
            includer_text = stripall(Base.read(includer_path, String))
            @test occursin("ismultios=true", includer_text)
            @test occursin("ismultiversion=true", includer_text)

            @test occursin(stripall("""
            @static if !should_precompile
                # nothing
            elseif !ismultios && !ismultiversion
                include("../deps/SnoopCompile/precompile/precompile_TestPackage.jl")
                _precompile_()
            else
                @static if Sys.islinux()
                    @static if VERSION <= v"1.0.0"
                        include("../deps/SnoopCompile/precompile/linux/1.0.0/precompile_TestPackage.jl")
                        _precompile_()
                    elseif VERSION <= v"1.4.1"
                        include("../deps/SnoopCompile/precompile/linux/1.4.1/precompile_TestPackage.jl")
                        _precompile_()
                    else
                    end

                elseif Sys.iswindows()
                    @static if VERSION <= v"1.0.0"
                        include("../deps/SnoopCompile/precompile/windows/1.0.0/precompile_TestPackage.jl")
                        _precompile_()
                    elseif VERSION <= v"1.4.1"
                        include("../deps/SnoopCompile/precompile/windows/1.4.1/precompile_TestPackage.jl")
                        _precompile_()
                    else
                    end

                else
                end

            end
            """), includer_text)
        end

    end

    using Pkg;
    package_name = "TestPackage"
    package_path = joinpath(pwd(),"$package_name.jl")
    Pkg.develop(PackageSpec(path=package_path))

    package_name2 = "TestPackage2"
    package_path2 = joinpath(pwd(),"$package_name2.jl")
    Pkg.develop(PackageSpec(path=package_path2))

    package_name3 = "TestPackage3"
    package_path3 = joinpath(pwd(),"$package_name3.jl")
    Pkg.develop(PackageSpec(path=package_path3))

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

        @testset "snoopi_bot_multiversion" begin
            cd(package_path3)

            os, osfun = SnoopCompile.detectOS()

            include("TestPackage3.jl/deps/SnoopCompile/snoopi_bot_multiversion.jl")

            @test isfile("deps/SnoopCompile/precompile/$VERSION/precompile_TestPackage3.jl")

            precompile_text = Base.read("deps/SnoopCompile/precompile/$VERSION/precompile_TestPackage3.jl", String)

            if VERSION > v"1.3"
                @test occursin("hello3", precompile_text)
                @test !occursin("domath3", precompile_text)
                @test !occursin("multiply3", precompile_text)
            elseif VERSION > v"1.0"
                @test !occursin("hello3", precompile_text)
                @test occursin("domath3", precompile_text)
                @test !occursin("multiply3", precompile_text)
            else
                @test !occursin("hello3", precompile_text)
                @test !occursin("domath3", precompile_text)
                @test occursin("multiply3", precompile_text)
            end
        end

        @testset "snoopi_bench-multiversion" begin
            cd(package_path3)
            include("TestPackage3.jl/deps/SnoopCompile/snoopi_bench.jl")
        end

        # workflow.yml file is tested online:
        # https://github.com/aminya/Example.jl/actions
    end
end
