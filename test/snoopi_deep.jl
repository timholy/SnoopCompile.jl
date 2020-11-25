using SnoopCompile
using SnoopCompile.SnoopCompileCore
using Test

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

    timing = SnoopCompileCore.@snoopi_deep begin
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

@testset "module_roots" begin
    @eval module M
        f(x) = x < 0.5
    end
    filter(M.f, [0, 1])  # warmup
    @eval module M
        f(x) = x < 0.5
    end
    timing = SnoopCompileCore.@snoopi_deep begin
        filter(M.f, [0, 1])
    end
    # It's important to build the inclusive times only once, because otherwise `==` will fail in `mroot ∈ broot.children`
    timingi = SnoopCompile.build_inclusive_times(timing)
    mroot = only(module_roots(M, timingi))
    broot = only(module_roots(Base, timingi))
    @test mroot != broot
    @test mroot ∈ broot.children
    io = IOBuffer()
    show(io, mroot)
    @test endswith(String(take!(io)), "MethodInstance for f(::Int64) with 0 direct children")
end

@testset "flamegraph_export" begin
    @eval module M  # Take another timing
        i(x) = x+5
        h(a::Array) = i(a[1]::Integer) + 2
        g(y::Integer) = h(Any[y])
    end

    timing = SnoopCompileCore.@snoopi_deep begin
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
