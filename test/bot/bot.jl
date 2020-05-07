using SnoopCompile, Test
import SnoopCompile.goodjoinpath
stripall(x::String) = replace(x, r"\s|\n"=>"")

snoopcompiledir = pwd()
bottestdir = GoodPath(@__DIR__)

@testset "bot" begin

    @testset "add_includer" begin
        package_name = "TestPackage0"
        package_path = goodjoinpath(bottestdir,"$package_name.jl","src","$package_name.jl")
        includer_path = goodjoinpath(dirname(package_path), "precompile_includer.jl")

        SnoopCompile.add_includer(package_name, package_path)

        @test occursin("include(\"precompile_includer.jl\")", stripall(Base.read(package_path, String)))
    end

    @testset "precompile de/activation" begin
        package_name = "TestPackage0"
        package_path = goodjoinpath(bottestdir,"$package_name.jl","src","$package_name.jl")
        precompiles_rootpath = goodjoinpath(bottestdir,"$package_name.jl","deps/SnoopCompile/precompile")
        includer_path = goodjoinpath(dirname(package_path), "precompile_includer.jl")

        SnoopCompile.new_includer_file(package_name, package_path, precompiles_rootpath, nothing, nothing, nothing, nothing)

        SnoopCompile.precompile_deactivator(package_path)
        @test occursin("should_precompile=false", stripall(Base.read(includer_path, String)))

        SnoopCompile.precompile_activator(package_path)
        includer_text = stripall(Base.read(includer_path, String))
        @test occursin("should_precompile=true", includer_text)

        rm(includer_path)
    end

    @testset "precompile new_includer_file" begin
        package_name = "TestPackage0"
        package_path = goodjoinpath(bottestdir,"$package_name.jl","src","$package_name.jl")
        precompiles_rootpath = "$(dirname(dirname(package_path)))/deps/SnoopCompile/precompile"
        precompiles_rootpath_rel = GoodPath(relpath( precompiles_rootpath , dirname(package_path)))
        includer_path = goodjoinpath(dirname(package_path), "precompile_includer.jl")


        @testset "no os, no else_os, no version, no else_version" begin
            SnoopCompile.new_includer_file(package_name, package_path, precompiles_rootpath, nothing, nothing, nothing, nothing)
            includer_text = stripall(Base.read(includer_path, String))
            @test occursin("ismultios=false", includer_text)
            @test occursin("ismultiversion=false", includer_text)

            @test occursin(stripall("""
            @static if !should_precompile
                # nothing
            elseif !ismultios && !ismultiversion
                include("$precompiles_rootpath_rel/precompile_$package_name.jl")
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
                include("$precompiles_rootpath_rel/precompile_$package_name.jl")
                _precompile_()
            else
                @static if Sys.islinux()
                    include("$precompiles_rootpath_rel/linux/precompile_$package_name.jl")
                    _precompile_()
                elseif Sys.iswindows()
                    include("$precompiles_rootpath_rel/windows/precompile_$package_name.jl")
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
                include("$precompiles_rootpath_rel/precompile_$package_name.jl")
                _precompile_()
            else
                @static if Sys.islinux()
                    include("$precompiles_rootpath_rel/linux/precompile_$package_name.jl")
                    _precompile_()
                elseif Sys.iswindows()
                    include("$precompiles_rootpath_rel/windows/precompile_$package_name.jl")
                    _precompile_()
                else
                    include("$precompiles_rootpath_rel/linux/precompile_$package_name.jl")
                    _precompile_()
                end

            end
            """), includer_text)
        end

        @testset "no os, no else_os, yes version, no else_version" begin
            SnoopCompile.new_includer_file(package_name, package_path, precompiles_rootpath, nothing, nothing, [v"1.2", v"1.4.1"], nothing)
            includer_text = stripall(Base.read(includer_path, String))
            @test occursin("ismultios=false", includer_text)
            @test occursin("ismultiversion=true", includer_text)

            @test occursin(stripall("""
            @static if !should_precompile
                # nothing
            elseif !ismultios && !ismultiversion
                include("$precompiles_rootpath_rel/precompile_TestPackage0.jl")
                _precompile_()
            else
                @static if VERSION < v"1.2.0"
                    # nothing - `snoopi_bot` isn't supported for `VERSION < v"1.2"` yet.
                elseif VERSION <= v"1.2.0"
                    include("$precompiles_rootpath_rel//1.2.0/precompile_TestPackage0.jl")
                    _precompile_()
                elseif VERSION <= v"1.4.1"
                    include("$precompiles_rootpath_rel//1.4.1/precompile_TestPackage0.jl")
                    _precompile_()
                else
                end

            end
            """), includer_text)
        end


        @testset "no os, no else_os, yes version, yes else_version" begin
            SnoopCompile.new_includer_file(package_name, package_path, precompiles_rootpath, nothing, nothing, [v"1.2", v"1.4.1"], v"1.4.1")
            includer_text = stripall(Base.read(includer_path, String))
            @test occursin("ismultios=false", includer_text)
            @test occursin("ismultiversion=true", includer_text)

            @test occursin(stripall("""
            @static if !should_precompile
                # nothing
            elseif !ismultios && !ismultiversion
                include("$precompiles_rootpath_rel/precompile_$package_name.jl")
                _precompile_()
            else
                @static if VERSION < v"1.2.0"
                    # nothing - `snoopi_bot` isn't supported for `VERSION < v"1.2"` yet.
                elseif VERSION <= v"1.2.0"
                    include("$precompiles_rootpath_rel//1.2.0/precompile_$package_name.jl")
                    _precompile_()
                elseif VERSION <= v"1.4.1"
                    include("$precompiles_rootpath_rel//1.4.1/precompile_$package_name.jl")
                    _precompile_()
                else
                    include("$precompiles_rootpath_rel//1.4.1/precompile_$package_name.jl")
                    _precompile_()
                end

            end
            """), includer_text)
        end

        @testset "yes os, yes else_os, yes version, no else_version" begin
            SnoopCompile.new_includer_file(package_name, package_path, precompiles_rootpath, ["linux", "windows"], "linux", [v"1.2", v"1.4.1"], nothing)
            includer_text = stripall(Base.read(includer_path, String))
            @test occursin("ismultios=true", includer_text)
            @test occursin("ismultiversion=true", includer_text)

            @test occursin(stripall("""
            @static if !should_precompile
                # nothing
            elseif !ismultios && !ismultiversion
                include("$precompiles_rootpath_rel/precompile_$package_name.jl")
                _precompile_()
            else
                @static if Sys.islinux()
                    @static if VERSION < v"1.2.0"
                        # nothing - `snoopi_bot` isn't supported for `VERSION < v"1.2"` yet.
                    elseif VERSION <= v"1.2.0"
                        include("$precompiles_rootpath_rel/linux/1.2.0/precompile_$package_name.jl")
                        _precompile_()
                    elseif VERSION <= v"1.4.1"
                        include("$precompiles_rootpath_rel/linux/1.4.1/precompile_$package_name.jl")
                        _precompile_()
                    else
                    end

                elseif Sys.iswindows()
                    @static if VERSION < v"1.2.0"
                        # nothing - `snoopi_bot` isn't supported for `VERSION < v"1.2"` yet.
                    elseif VERSION <= v"1.2.0"
                        include("$precompiles_rootpath_rel/windows/1.2.0/precompile_$package_name.jl")
                        _precompile_()
                    elseif VERSION <= v"1.4.1"
                        include("$precompiles_rootpath_rel/windows/1.4.1/precompile_$package_name.jl")
                        _precompile_()
                    else
                    end

                else
                    @static if VERSION < v"1.2.0"
                        # nothing - `snoopi_bot` isn't supported for `VERSION < v"1.2"` yet.
                    elseif VERSION <= v"1.2.0"
                        include("$precompiles_rootpath_rel/linux/1.2.0/precompile_$package_name.jl")
                        _precompile_()
                    elseif VERSION <= v"1.4.1"
                        include("$precompiles_rootpath_rel/linux/1.4.1/precompile_$package_name.jl")
                        _precompile_()
                    else
                    end

                end

            end
            """), includer_text)
        end

        @testset "yes os, yes else_os, yes version, yes else_version" begin
            SnoopCompile.new_includer_file(package_name, package_path, precompiles_rootpath, ["linux", "windows"], "linux", [v"1.2", v"1.4.1"], v"1.4.1")
            includer_text = stripall(Base.read(includer_path, String))
            @test occursin("ismultios=true", includer_text)
            @test occursin("ismultiversion=true", includer_text)

            @test occursin(stripall("""
            @static if !should_precompile
                # nothing
            elseif !ismultios && !ismultiversion
                include("$precompiles_rootpath_rel/precompile_$package_name.jl")
                _precompile_()
            else
                @static if Sys.islinux()
                    @static if VERSION < v"1.2.0"
                        # nothing - `snoopi_bot` isn't supported for `VERSION < v"1.2"` yet.
                    elseif VERSION <= v"1.2.0"
                        include("$precompiles_rootpath_rel/linux/1.2.0/precompile_$package_name.jl")
                        _precompile_()
                    elseif VERSION <= v"1.4.1"
                        include("$precompiles_rootpath_rel/linux/1.4.1/precompile_$package_name.jl")
                        _precompile_()
                    else
                        include("$precompiles_rootpath_rel/linux/1.4.1/precompile_$package_name.jl")
                        _precompile_()
                    end

                elseif Sys.iswindows()
                    @static if VERSION < v"1.2.0"
                        # nothing - `snoopi_bot` isn't supported for `VERSION < v"1.2"` yet.
                    elseif VERSION <= v"1.2.0"
                        include("$precompiles_rootpath_rel/windows/1.2.0/precompile_$package_name.jl")
                        _precompile_()
                    elseif VERSION <= v"1.4.1"
                        include("$precompiles_rootpath_rel/windows/1.4.1/precompile_$package_name.jl")
                        _precompile_()
                    else
                        include("$precompiles_rootpath_rel/windows/1.4.1/precompile_$package_name.jl")
                        _precompile_()
                    end

                else
                    @static if VERSION < v"1.2.0"
                        # nothing - `snoopi_bot` isn't supported for `VERSION < v"1.2"` yet.
                    elseif VERSION <= v"1.2.0"
                        include("$precompiles_rootpath_rel/linux/1.2.0/precompile_$package_name.jl")
                        _precompile_()
                    elseif VERSION <= v"1.4.1"
                        include("$precompiles_rootpath_rel/linux/1.4.1/precompile_$package_name.jl")
                        _precompile_()
                    else
                        include("$precompiles_rootpath_rel/linux/1.4.1/precompile_$package_name.jl")
                        _precompile_()
                    end

                end

            end
            """), includer_text)
        end

        @testset "yes os, no else_os, yes version, no else_version" begin
            SnoopCompile.new_includer_file(package_name, package_path, precompiles_rootpath, ["linux", "windows"], nothing, [v"1.2", v"1.4.1"], nothing)
            includer_text = stripall(Base.read(includer_path, String))
            @test occursin("ismultios=true", includer_text)
            @test occursin("ismultiversion=true", includer_text)

            @test occursin(stripall("""
            @static if !should_precompile
                # nothing
            elseif !ismultios && !ismultiversion
                include("$precompiles_rootpath_rel/precompile_TestPackage0.jl")
                _precompile_()
            else
                @static if Sys.islinux()
                    @static if VERSION < v"1.2.0"
                        # nothing - `snoopi_bot` isn't supported for `VERSION < v"1.2"` yet.
                    elseif VERSION <= v"1.2.0"
                        include("$precompiles_rootpath_rel/linux/1.2.0/precompile_TestPackage0.jl")
                        _precompile_()
                    elseif VERSION <= v"1.4.1"
                        include("$precompiles_rootpath_rel/linux/1.4.1/precompile_TestPackage0.jl")
                        _precompile_()
                    else
                    end

                elseif Sys.iswindows()
                    @static if VERSION < v"1.2.0"
                        # nothing - `snoopi_bot` isn't supported for `VERSION < v"1.2"` yet.
                    elseif VERSION <= v"1.2.0"
                        include("$precompiles_rootpath_rel/windows/1.2.0/precompile_TestPackage0.jl")
                        _precompile_()
                    elseif VERSION <= v"1.4.1"
                        include("$precompiles_rootpath_rel/windows/1.4.1/precompile_TestPackage0.jl")
                        _precompile_()
                    else
                    end

                else
                end

            end
            """), includer_text)
        end
        rm(includer_path)
    end


    if VERSION >=  v"1.2"

        using Pkg
        for (i, package_name) in enumerate(["TestPackage1", "TestPackage2", "TestPackage3", "TestPackage4"])
            Pkg.develop(PackageSpec(path=joinpath(bottestdir,"$package_name.jl")))
            @eval $(Symbol("package_rootpath", i)) = goodjoinpath(bottestdir,"$($package_name).jl")
        end

        @testset "snoopi_bot" begin

            include("$package_rootpath1/deps/SnoopCompile/snoopi_bot.jl")

            @test isfile("$package_rootpath1/deps/SnoopCompile/precompile/precompile_TestPackage1.jl")

            precompile_text = Base.read("$package_rootpath1/deps/SnoopCompile/precompile/precompile_TestPackage1.jl", String)

            @test occursin("hello", precompile_text)
            @test occursin("domath", precompile_text)
        end

        @testset "snoopi_bench" begin
            include("$package_rootpath1/deps/SnoopCompile/snoopi_bench.jl")
        end

        @testset "snoopi_bot_multios" begin
            os, osfun = SnoopCompile.detectOS()

            include("$package_rootpath2/deps/SnoopCompile/snoopi_bot_multios.jl")

            @test isfile("$package_rootpath2/deps/SnoopCompile/precompile/$os/precompile_TestPackage2.jl")

            precompile_text = Base.read("$package_rootpath2/deps/SnoopCompile/precompile/$os/precompile_TestPackage2.jl", String)

            if os == "windows"
                @test occursin("hello2", precompile_text)
                @test !occursin("domath2", precompile_text)
            else
                @test !occursin("hello2", precompile_text)
                @test occursin("domath2", precompile_text)
            end
        end

        @testset "snoopi_bench-multios" begin
            include("$package_rootpath2/deps/SnoopCompile/snoopi_bench.jl")
        end

        @testset "snoopi_bot_multiversion" begin
            os, osfun = SnoopCompile.detectOS()

            include("$package_rootpath3/deps/SnoopCompile/snoopi_bot_multiversion.jl")

            @test isfile("$package_rootpath3/deps/SnoopCompile/precompile/$VERSION/precompile_TestPackage3.jl")

            precompile_text = Base.read("$package_rootpath3/deps/SnoopCompile/precompile/$VERSION/precompile_TestPackage3.jl", String)

            if VERSION > v"1.3"
                @test occursin("hello3", precompile_text)
                @test !occursin("domath3", precompile_text)
                @test !occursin("multiply3", precompile_text)
            elseif VERSION > v"1.2"
                @test !occursin("hello3", precompile_text)
                @test occursin("domath3", precompile_text)
                @test !occursin("multiply3", precompile_text)
            else
                @test !occursin("hello3", precompile_text)
                @test !occursin("domath3", precompile_text)
                @test occursin("multiply3", precompile_text)
            end
        end

        if VERSION <=  v"1.4.1"
            @testset "snoopi_bench-multiversion" begin
                include("$package_rootpath3/deps/SnoopCompile/snoopi_bench.jl")
            end
        else
            @warn "else version is set to 1.2, so we should not run the benchmark test on nightly, when we have not generated such files yet (unlike in the realworld tests)."
        end

        @testset "snoopi_bot_function_form" begin

            include("$package_rootpath4/deps/SnoopCompile/snoopi_bot.jl")

            @test isfile("$package_rootpath4/deps/SnoopCompile/precompile/precompile_TestPackage4.jl")

            precompile_text = Base.read("$package_rootpath4/deps/SnoopCompile/precompile/precompile_TestPackage4.jl", String)

            @test occursin("hello4", precompile_text)
            @test occursin("domath4", precompile_text)
        end

        @testset "snoopi_bench_function_form" begin
            include("$package_rootpath4/deps/SnoopCompile/snoopi_bench.jl")
        end

        for package_name in ["TestPackage1", "TestPackage2", "TestPackage3", "TestPackage4"]
            Pkg.rm(package_name)
        end
        Pkg.resolve()

        # workflow yaml file is tested online:
        # https://github.com/aminya/Example.jl/actions
    end

    # just in case
    cd(snoopcompiledir)
end
