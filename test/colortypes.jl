using SnoopCompile, Test, Pkg

@testset "ColorTypes" begin
    success, line, modsym = SnoopCompile.parse_call("Tuple{typeof(ColorTypes.to_top), Type{C}} where C<:(ColorTypes.Colorant{T, N} where N where T)")
    @test success
    @test modsym == :ColorTypes

    mktempdir() do tmpdir
        tmpfile = joinpath(tmpdir, "colortypes_compiles.csv")
        tmpdir2 = joinpath(tmpdir, "precompile")
        tmpfile2 = joinpath(tmpdir, "userimg_ColorTypes.jl")

        ### Log the compiles (in a separate process)
        SnoopCompile.@snoopc tmpfile begin
            using ColorTypes, Pkg
            include(joinpath(dirname(dirname(pathof(ColorTypes))), "test", "runtests.jl"))
        end

        ### Parse the compiles and generate precompilation scripts
        let data = SnoopCompile.read(tmpfile)
            # Use these two lines if you want to create precompile functions for
            # individual packages
            pc = SnoopCompile.parcel(reverse!(data[2]))
            SnoopCompile.write(tmpdir2, pc)

            # Use these two lines if you want to add to your userimg.jl
            pc = SnoopCompile.format_userimg(reverse!(data[2]))
            SnoopCompile.write(tmpfile2, pc)
        end

        function notisempty(filename, minlength)
            @test isfile(filename)
            @test length(readlines(filename)) >= minlength
            nothing
        end

        notisempty(joinpath(tmpdir2, "precompile_ColorTypes.jl"), 100)
        notisempty(joinpath(tmpdir2, "precompile_FixedPointNumbers.jl"), 2)
        notisempty(tmpfile2, 100)
    end
end
