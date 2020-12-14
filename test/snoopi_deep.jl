using SnoopCompile
using SnoopCompile.SnoopCompileCore
using Test
using InteractiveUtils
using Random
using Profile
using PyPlot: PyPlot, plt

using AbstractTrees  # For FlameGraphs tests

@testset "@snoopi_deep" begin
    # WARMUP (to compile all the small, reachable methods)
    @eval module M  # Example with some functions that include type instability
        i(x) = x+5
        h(a::Array) = i(a[1]::Integer) + 2
        g(y::Integer) = h(Any[y])
    end
    M.g(2)  # Warmup all deeply reachable functions
    M.g(true)

    # Redefine the module, so the snoop will only show these functions:
    @eval module M  # Example with some functions that include type instability
        i(x) = x+5
        h(a::Array) = i(a[1]::Integer) + 2
        g(y::Integer) = h(Any[y])
    end

    timing = @snoopi_deep begin
        M.g(2)
        M.g(true)
    end
    times = flatten_times(timing)
    @test length(times) == 7  # ROOT, g(::Int), g(::Bool), h(...), i(::Integer), i(::Int), i(::Bool)
    names = [mi_info.mi.def.name for (time, mi_info) in times]
    @test sort(names) == [:ROOT, :g, :g, :h, :i, :i, :i]

    longest_frame_time = times[end][1]
    @test length(flatten_times(timing, tmin_secs=longest_frame_time)) == 1

    timesm = accumulate_by_source(times)
    @test length(timesm) == 4
    names = [m.name for (time, m) in timesm]
    @test sort(names) == [:ROOT, :g, :h, :i]
    longest_method_time = timesm[end][1]
    @test length(accumulate_by_source(times; tmin_secs=longest_method_time)) == 1

    # Also check module-level thunks
    @eval module M  # Example with some functions that include type instability
        i(x) = x+5
        h(a::Array) = i(a[1]::Integer) + 2
        g(y::Integer) = h(Any[y])
    end
    timingmod = @snoopi_deep begin
        @eval @testset "Outer" begin
            @testset "Inner" begin
                for i = 1:2 M.g(2) end
            end
        end
    end
    times = flatten_times(timingmod)
    timesm = accumulate_by_source(times)
    timesmod = filter(pr -> isa(pr.second, Core.MethodInstance), timesm)
    @test length(timesmod) == 1
end

@testset "flamegraph_export" begin
    @eval module M  # Take another timing
        i(x) = x+5
        h(a::Array) = i(a[1]::Integer) + 2
        g(y::Integer) = h(Any[y])
    end

    timing = @snoopi_deep begin
        M.g(2)
    end
    times = flatten_times(timing)

    fg = SnoopCompile.flamegraph(timing)
    @test length(collect(AbstractTrees.PreOrderDFS(fg))) == 5
    # Test that the span covers the whole tree.
    for leaf in AbstractTrees.PreOrderDFS(fg)
        @test leaf.data.span.start in fg.data.span
        @test leaf.data.span.stop in fg.data.span
    end

    t1, t2 = times[1][1], times[2][1]
    # Ensure there's a timing gap, and that cutting off the fastest-to-infer won't leave the tree headless
    if t1 != t2 && times[1][2].mi.def.name !== :g
        cutoff_bottom_frame = (t1 + t2) / 2
        fg2 = SnoopCompile.flamegraph(timing, tmin_secs = cutoff_bottom_frame)
        @test length(collect(AbstractTrees.PreOrderDFS(fg2))) == (length(collect(AbstractTrees.PreOrderDFS(fg))) - 1)
    end
end

include("testmodules/SnoopBench.jl")
@testset "parcel" begin
    a = SnoopBench.A()
    tinf = @snoopi_deep SnoopBench.f1(a)
    ttot, prs = SnoopCompile.parcel(tinf)
    mod, (tmod, tmis) = only(prs)
    @test mod === SnoopBench
    t, mi = only(tmis)
    @test ttot == tmod == t  # since there is only one
    @test mi.def.name === :f1

    A = [a]
    tinf = @snoopi_deep SnoopBench.mappushes(identity, A)
    ttot, prs = SnoopCompile.parcel(tinf)
    mod, (tmod, tmis) = only(prs)
    @test mod === SnoopBench
    @test ttot == tmod  # since there is only one
    @test length(tmis) == 2
    io = IOBuffer()
    SnoopCompile.write(io, tmis; tmin=0.0)
    str = String(take!(io))
    @test occursin(r"typeof\(mappushes\),Any,Vector\{A\}", str)
    @test occursin(r"typeof\(mappushes!\),typeof\(identity\),Vector\{Any\},Vector\{A\}", str)

    list = Any[1, 1.0, Float16(1.0), a]
    tinf = @snoopi_deep SnoopBench.mappushes(isequal(Int8(1)), list)
    ttot, prs = SnoopCompile.parcel(tinf)
    @test length(prs) == 2
    _, (tmodBase, tmis) = prs[findfirst(pr->pr.first === Base, prs)]
    tw, nw = SnoopCompile.write(io, tmis; tmin=0.0)
    @test 0.0 <= tw <= tmodBase && 0 <= nw <= length(tmis)-1
    str = String(take!(io))
    @test !occursin(r"Base.Fix2\{typeof\(isequal\).*SnoopBench.A\}", str)
    @test length(split(chomp(str), '\n')) == nw
    _, (tmodBench, tmis) = prs[findfirst(pr->pr.first === SnoopBench, prs)]
    @test tmodBench + tmodBase ≈ ttot
    tw, nw = SnoopCompile.write(io, tmis; tmin=0.0)
    @test nw == 2
    str = String(take!(io))
    @test occursin(r"typeof\(mappushes\),Any,Vector\{Any\}", str)
    @test occursin(r"typeof\(mappushes!\),Base.Fix2\{typeof\(isequal\).*\},Vector\{Any\},Vector\{Any\}", str)

    td = joinpath(tempdir(), randstring(8))
    SnoopCompile.write(td, prs; tmin=0.0, ioreport=io)
    str = String(take!(io))
    @test occursin(r"Base: precompiled [\d\.]+ out of [\d\.]+", str)
    @test occursin(r"SnoopBench: precompiled [\d\.]+ out of [\d\.]+", str)
    file_base = joinpath(td, "precompile_Base.jl")
    @test isfile(file_base)
    @test occursin("ccall(:jl_generating_output", read(file_base, String))
    rm(td, recursive=true, force=true)
    SnoopCompile.write(td, prs; ioreport=io, header=false)
    str = String(take!(io))  # just to clear it in case we use it again
    @test !occursin("ccall(:jl_generating_output", read(file_base, String))
    rm(td, recursive=true, force=true)
end

@testset "Specialization" begin
    Ts = subtypes(Any)
    tinf_unspec = @snoopi_deep SnoopBench.mappushes(SnoopBench.spell_unspec, Ts)
    tinf_spec =   @snoopi_deep SnoopBench.mappushes(SnoopBench.spell_spec, Ts)
    tf_unspec = flatten_times(tinf_unspec)
    tf_spec   = flatten_times(tinf_spec)
    @test length(tf_unspec) < 10
    @test any(tmi -> occursin("spell_unspec(::Any)", repr(tmi[2])), tf_unspec)
    @test length(tf_spec) >= length(Ts)
    @test !any(tmi -> occursin("spell_spec(::Any)", repr(tmi[2])), tf_unspec)

    fig, axs = plt.subplots(1, 2)

    nruns = 10^3
    @profile for i = 1:nruns
        SnoopBench.mappushes(SnoopBench.spell_spec, Ts)
    end
    rit = runtime_inferencetime(tinf_spec)
    m = @which SnoopBench.spell_spec(first(Ts))
    tr, ti, nspec = rit[findfirst(pr -> pr.first == m, rit)].second
    @test ti > tr
    @test nspec >= length(Ts)
    specialization_plot(axs[1], rit; interactive=false)

    Profile.clear()
    @profile for i = 1:nruns
        SnoopBench.mappushes(SnoopBench.spell_unspec, Ts)
    end
    rit = runtime_inferencetime(tinf_unspec)
    m = @which SnoopBench.spell_unspec(first(Ts))
    tr, ti, nspec = rit[findfirst(pr -> pr.first == m, rit)].second
    @test ti < tr
    @test nspec == 1
    specialization_plot(axs[2], rit; interactive=false)
end
