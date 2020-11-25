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

    # Redefine the module, so the snoop will only show these functions:
    @eval module M  # Example with some functions that include type instability
        i(x) = x+5
        h(a::Array) = i(a[1]::Integer) + 2
        g(y::Integer) = h(Any[y])
    end

    timing = SnoopCompileCore.@snoopi_deep begin
        M.g(2)
    end
    times = SnoopCompile.flatten_times(timing)
    @test length(times) == 5  # ROOT, g(...), h(...), i(::Integer), i(::Int)
    names = [mi_info.mi.def.name for (time, mi_info) in times]
    @test sort(names) == [:ROOT, :g, :h, :i, :i]

    longest_frame_time = times[end][1]
    @test length(SnoopCompile.flatten_times(timing, tmin_secs=longest_frame_time)) == 1
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
    times = SnoopCompile.flatten_times(timing)

    fg = SnoopCompile.flamegraph(timing)
    @test length(collect(AbstractTrees.PreOrderDFS(fg))) == 5
    # Test that the span covers the whole tree.
    for leaf in AbstractTrees.PreOrderDFS(fg)
        @test leaf.data.span.start in fg.data.span
        @test leaf.data.span.stop in fg.data.span
    end

    t1, t2 = times[1][1], times[2][1]
    if t1 != t2   # in rare cases it happens that the bottom two have the same time, but the test requires a gap
        cutoff_bottom_frame = (t1 + t2) / 2
        fg2 = SnoopCompile.flamegraph(timing, tmin_secs = cutoff_bottom_frame)
        @test length(collect(AbstractTrees.PreOrderDFS(fg2))) == (length(collect(AbstractTrees.PreOrderDFS(fg))) - 1)
    end
end
