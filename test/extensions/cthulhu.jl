module CthulhuExtTest

using SnoopCompileCore, SnoopCompile
using Cthulhu
using Pkg
using Test

if !isdefined(@__MODULE__, :fake_terminal)
    @eval (@__MODULE__) begin
        Base.include(@__MODULE__, normpath(pkgdir(Cthulhu), "test", "FakeTerminals.jl"))
        using .FakeTerminals
    end
end

macro with_try_stderr(out, expr)
    quote
        try
            $(esc(expr))
        catch err
            bt = catch_backtrace()
            Base.display_error(stderr, err, bt)
        end
    end
end

# Test functions
myplus(x, y) = x + y
function f(x)
    x < 0.25 ? 1 :
    x < 0.5  ? 1.0 :
    x < 0.75 ? 0x01 : Float16(1)
end
g(c) = myplus(f(c[1]), f(c[2]))


@testset "Cthulhu extension" begin
    @testset "ascend for invalidations" begin
        cproj = Base.active_project()
        cd(joinpath(dirname(@__DIR__), "testmodules", "Invalidation")) do
            Pkg.activate(pwd())
            Pkg.develop(path="./PkgC")
            Pkg.develop(path="./PkgD")
            Pkg.precompile()
            invalidations = @snoop_invalidations begin
                @eval begin
                    using PkgC
                    PkgC.nbits(::UInt8) = 8
                    using PkgD
                end
            end
            tree = only(invalidation_trees(invalidations))
            sig, root = only(tree.mt_backedges)

            fake_terminal() do term, in, out, _
                t = @async begin
                    @with_try_stderr out ascend(term, root; interruptexc=false)
                end
                lines = String(readavailable(out))   # this gets the header
                lines = String(readavailable(out))
                @test occursin("call_nbits", lines)
                @test occursin("map_nbits(::Vector{Integer})", lines)
                # the job of the extension is done  once we've written the menu, so we can quit here
                write(in, 'q')
                wait(t)
            end
        end

        Pkg.activate(cproj)
    end

    @testset "ascend for inference triggers" begin
        tinf = @snoop_inference g([0.7, 0.8])
        itrigs = inference_triggers(tinf; exclude_toplevel=false)
        itrig = last(itrigs)

        fake_terminal() do term, in, out, _
            t = @async begin
                @with_try_stderr out ascend(term, itrig; interruptexc=false)
            end
            lines = String(readavailable(out))   # this gets the header
            lines = String(readavailable(out))
            @test occursin("myplus(::UInt8, ::Float16)", lines)
            @test occursin("g(::Vector{Float64})", lines)
            # the job of the extension is done  once we've written the menu, so we can quit here
            write(in, 'q')
            wait(t)
        end
    end
end

end
