# Using `@snoopi_deep` results to generate precompile directives

Improving inferrability, specialization, and precompilability may sometimes feel like "eating your vegetables": really good for you, but it sometimes feels like work.  (Depending on tastes; I love vegetables.)
While we've already gotten some payoff, now we're going to collect an additional reward for our hard work: the "dessert" of adding `precompile` directives.
It's worth emphasing that if we hadn't done the analysis of inference triggers and made improvements to our package, the benefit of adding `precompile` directives would have been substantially smaller.

## Parcel

`precompile` directives have to be emitted by the module that owns the method.
SnoopCompile comes with a tool, `parcel`, that splits out the "root-most" precompilable MethodInstances into their constituent modules.
In our case, since we've made almost every call precompilable, this will typically correspond to the bottom row of boxes in the flame graph.
In cases where you have some non-precompilable MethodInstances, they will include MethodInstances from higher up in the call tree.

Let's use `SnoopCompile.parcel` on `OptimizeMeFixed`:

```julia
julia> ttot, pcs = SnoopCompile.parcel(tinf);

julia> ttot
0.80544499

julia> pcs
4-element Vector{Pair{Module, Tuple{Float64, Vector{Tuple{Float64, Core.MethodInstance}}}}}:
                 Core => (0.00010728, [(0.00010728, MethodInstance for (NamedTuple{(:sizehint,), T} where T<:Tuple)(::Tuple{Int64}))])
                 Base => (0.023301831000000002, [(2.577e-5, MethodInstance for getproperty(::IOBuffer, ::Symbol)), (3.9483e-5, MethodInstance for ==(::Type, ::Nothing)), (5.104e-5, MethodInstance for typeinfo_eltype(::Type)), (0.000325206, MethodInstance for show(::IOContext{IOBuffer}, ::Any)), (0.000351546, MethodInstance for IOContext(::IOBuffer, ::IOContext{Base.TTY})), (0.000409676, MethodInstance for Pair{Symbol, DataType}(::Any, ::Any)), (0.000651708, MethodInstance for print(::IOContext{Base.TTY}, ::String, ::String, ::Vararg{String, N} where N)), (0.001187032, MethodInstance for Pair(::Symbol, ::Type)), (0.0015947350000000001, MethodInstance for show(::IOContext{IOBuffer}, ::UInt16)), (0.008491582000000001, MethodInstance for show(::IOContext{IOBuffer}, ::Tuple{String, Int64})), (0.010174053, MethodInstance for show(::IOContext{IOBuffer}, ::Vector{Int64}))])
             Base.Ryu => (0.12526549099999998, [(0.03687417999999999, MethodInstance for writeshortest(::Vector{UInt8}, ::Int64, ::Float32, ::Bool, ::Bool, ::Bool, ::Int64, ::UInt8, ::Bool, ::UInt8, ::Bool, ::Bool)), (0.08839131099999999, MethodInstance for show(::IOContext{IOBuffer}, ::Float32))])
 Main.OptimizeMeFixed => (0.6468779330000002, [(0.10149027000000001, MethodInstance for show(::IOContext{Base.TTY}, ::MIME{Symbol("text/plain")}, ::Vector{Main.OptimizeMeFixed.Object})), (0.14666734500000003, MethodInstance for show(::IOContext{Base.TTY}, ::MIME{Symbol("text/plain")}, ::Vector{Main.OptimizeMeFixed.Container{Any}})), (0.39872031800000013, MethodInstance for main())])
```

This tells us that a total of 0.8s were spent on inference.
`parcel` discovered precompilable MethodInstances for four modules, `Core`, `Base`, `Base.Ryu`, and `OptimizeMeFixed`. These are listed in increasing order of inference time.

Let's look specifically at `OptimizeMeFixed`, since that's under our control:

```julia
julia> pcmod = pcs[end]
Main.OptimizeMeFixed => (0.6468779330000002, Tuple{Float64, Core.MethodInstance}[(0.10149027000000001, MethodInstance for show(::IOContext{Base.TTY}, ::MIME{Symbol("text/plain")}, ::Vector{Main.OptimizeMeFixed.Object})), (0.14666734500000003, MethodInstance for show(::IOContext{Base.TTY}, ::MIME{Symbol("text/plain")}, ::Vector{Main.OptimizeMeFixed.Container{Any}})), (0.39872031800000013, MethodInstance for main())])

julia> tmod, tpcs = pcmod.second;

julia> tmod
0.6468779330000002

julia> tpcs
3-element Vector{Tuple{Float64, Core.MethodInstance}}:
 (0.10149027000000001, MethodInstance for show(::IOContext{Base.TTY}, ::MIME{Symbol("text/plain")}, ::Vector{Main.OptimizeMeFixed.Object}))
 (0.14666734500000003, MethodInstance for show(::IOContext{Base.TTY}, ::MIME{Symbol("text/plain")}, ::Vector{Main.OptimizeMeFixed.Container{Any}}))
 (0.39872031800000013, MethodInstance for main())
```

0.65s of that time is due to `OptimizeMeFixed`, and `parcel` discovered three MethodInstances to precompile. `main()` is the most costly at nearly 0.4s.

We could look at the others similarly.

## SnoopCompile.write

You can generate files that contain ready-to-use `precompile` directives using `SnoopCompile.write`:

```julia
julia> SnoopCompile.write("/tmp/precompiles_OptimizeMe", pcs)
Core: no precompile statements out of 0.00010728
Base: precompiled 0.021447402 out of 0.023301831000000002
Base.Ryu: precompiled 0.12526549099999998 out of 0.12526549099999998
Main.OptimizeMeFixed: precompiled 0.6468779330000002 out of 0.6468779330000002
```

You'll now find a directory `/tmp/precompiles_OptimizeMe`, and inside you'll find three files, for `Base`, `Base.Ryu`, and `OptimizeMeFixed`, respectively.
The contents of the last of these should be recognizable:

```julia
function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    Base.precompile(Tuple{typeof(main)})   # time: 0.39872032
    Base.precompile(Tuple{typeof(show),IOContext{Base.TTY},MIME{Symbol("text/plain")},Vector{Container{Any}}})   # time: 0.14666735
    Base.precompile(Tuple{typeof(show),IOContext{Base.TTY},MIME{Symbol("text/plain")},Vector{Object}})   # time: 0.10149027
end
```

The first `ccall` line ensures we only pay the cost of running these `precompile` directives if we're building the package; this is relevant mostly if you're running Julia with `--compiled-modules=no` so it is rarely something that matters.
(It would also matter if you've set `__precompile__(false)` at the top of your module, but if so why are you reading this?)

This file is ready to be moved into the `OptimizeMe` repository and `include`d into your module definition.
In general it's recommended to do this inside a block

```julia
if Base.VERSION >= v"1.4.2"
    include("precompile.jl")
    _precompile_()
end
```

because earlier versions of Julia occasionally crashed on certain precompile directives.
It's also perfectly fine to use

```julia
if Base.VERSION >= v"1.4.2"
    Base.precompile(Tuple{typeof(main)})   # time: 0.39872032
    Base.precompile(Tuple{typeof(show),IOContext{Base.TTY},MIME{Symbol("text/plain")},Vector{Container{Any}}})   # time: 0.14666735
    Base.precompile(Tuple{typeof(show),IOContext{Base.TTY},MIME{Symbol("text/plain")},Vector{Object}})   # time: 0.10149027
end
```

directly in the `OptimizeMeFixed` module, usually as the last block of the module definition.

You might also consider submitting some of the other files (or their `precompile` directives) to the packages you depend on.
In some cases, the specific argument type combinations may be too "niche" to be worth specializing; one such case is found here, a `show` method for `Tuple{String, Int64}`.
But in other cases, these may be very worthy additions to the package.

## Final results

Let's check out the final results of adding these `precompile` directives to `OptimizeMeFixed`.
First, let's build both modules as precompiled packages:

```julia
ulia> push!(LOAD_PATH, ".")
4-element Vector{String}:
 "@"
 "@v#.#"
 "@stdlib"
 "."

julia> using OptimizeMe
[ Info: Precompiling OptimizeMe [top-level]

julia> using OptimizeMeFixed
[ Info: Precompiling OptimizeMeFixed [top-level]
```

Now in fresh sessions,

```julia
julia> @time (using OptimizeMe; OptimizeMe.main())
3.14 is great
2.718 is jealous
⋮
Object x: 7
  3.091609 seconds (10.62 M allocations: 581.374 MiB, 5.21% gc time, 99.67% compilation time)
```

versus

```julia
julia> @time (using OptimizeMeFixed; OptimizeMeFixed.main())
3.14 is great
2.718 is jealous
⋮
 Object x: 7
  1.806477 seconds (5.37 M allocations: 288.433 MiB, 5.10% gc time, 96.86% compilation time)
```

We've cut down on the latency by nearly a factor of two.
Moreover, if Julia someday caches generated code, we're well-prepared to capitalize on the benefits, because the same improvements in "code ownership" are almost certain to pay dividends there too.

If you inspect the results, you may suffer a few disappointments: some methods that we expected to precompile, particularly from our "soft" piracy `show` tricks, don't "take."
At the moment there appears to be a small subset of methods that fail to precompile, and the reasons are not yet widely understood.
At present, the best advice seems to be to comment-out any precompile directives that don't "take," since otherwise they increase the build time for the package without material benefit.
These failures may be addressed in future versions of Julia.
It's also worth appreciating how much we have succeeded in reducing latency, with the awareness that we may be able to get even greater benefit in the future.

## Summary

`@snoopi_deep` collects enough data to learn which methods are triggering inference, how heavily methods are being specialized, and so on.
Examining your code from the standpoint of inference and specialization may be unfamiliar at first, but like other aspects of package development (testing, documentation, and release compatibility management) it can lead to significant improvements in the quality-of-life for you and your users.
By optimizing your packages and then adding `precompile` directives, you can often cut down substantially on latency.
