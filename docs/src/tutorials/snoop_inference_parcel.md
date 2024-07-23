# [Using `@snoop_inference` to emit manual precompile directives](@id precompilation)

In a few cases, it may be inconvenient or impossible to precompile using a [workload](https://julialang.github.io/PrecompileTools.jl/stable/#Tutorial:-forcing-precompilation-with-workloads). Some examples might be:
- an application that opens graphical windows
- an application that connects to a database
- an application that creates, deletes, or rewrites files on disk

In such cases, one alternative is to create a manual list of precompile directives using Julia's `precompile(f, argtypes)` function.

!!! warning
    Manual precompile directives are much more likely to "go stale" as the package is developed---`precompile` does not throw an error if a method for the given `argtypes` cannot be found. They are also more likely to be dependent on the Julia version, operating system, or CPU architecture. Whenever possible, it's safer to use a workload.

`precompile` directives have to be emitted by the module that owns the method and/or types.
SnoopCompile comes with a tool, `parcel`, that splits out the "root-most" precompilable MethodInstances into their constituent modules.
This will typically correspond to the bottom row of boxes in the [flame graph](@ref flamegraph).
In cases where you have some non-precompilable MethodInstances, they will include MethodInstances from higher up in the call tree.

Let's use `SnoopCompile.parcel` on [`OptimizeMeFixed`](@ref inferrability):

```julia
julia> ttot, pcs = SnoopCompile.parcel(tinf);

julia> ttot
0.6084431670000001

julia> pcs
4-element Vector{Pair{Module, Tuple{Float64, Vector{Tuple{Float64, Core.MethodInstance}}}}}:
                 Core => (0.000135179, [(0.000135179, MethodInstance for (NamedTuple{(:sizehint,), T} where T<:Tuple)(::Tuple{Int64}))])
                 Base => (0.028383533000000002, [(3.2456e-5, MethodInstance for getproperty(::IOBuffer, ::Symbol)), (4.7474e-5, MethodInstance for ==(::Type, ::Nothing)), (5.7944e-5, MethodInstance for typeinfo_eltype(::Type)), (0.00039092299999999994, MethodInstance for show(::IOContext{IOBuffer}, ::Any)), (0.000433143, MethodInstance for IOContext(::IOBuffer, ::IOContext{Base.TTY})), (0.000484984, MethodInstance for Pair{Symbol, DataType}(::Any, ::Any)), (0.000742383, MethodInstance for print(::IOContext{Base.TTY}, ::String, ::String, ::Vararg{String, N} where N)), (0.001293705, MethodInstance for Pair(::Symbol, ::Type)), (0.0018914350000000003, MethodInstance for show(::IOContext{IOBuffer}, ::UInt16)), (0.010604793000000001, MethodInstance for show(::IOContext{IOBuffer}, ::Tuple{String, Int64})), (0.012404293, MethodInstance for show(::IOContext{IOBuffer}, ::Vector{Int64}))])
             Base.Ryu => (0.15733664599999997, [(0.05721630600000001, MethodInstance for writeshortest(::Vector{UInt8}, ::Int64, ::Float32, ::Bool, ::Bool, ::Bool, ::Int64, ::UInt8, ::Bool, ::UInt8, ::Bool, ::Bool)), (0.10012033999999997, MethodInstance for show(::IOContext{IOBuffer}, ::Float32))])
 Main.OptimizeMeFixed => (0.4204474180000001, [(0.4204474180000001, MethodInstance for main())])
```

This tells us that a total of ~0.6s were spent on inference.
`parcel` discovered precompilable MethodInstances for four modules, `Core`, `Base`, `Base.Ryu`, and `OptimizeMeFixed`.
These are listed in increasing order of inference time.

Let's look specifically at `OptimizeMeFixed`, since that's under our control:

```julia
julia> pcmod = pcs[end]
Main.OptimizeMeFixed => (0.4204474180000001, Tuple{Float64, Core.MethodInstance}[(0.4204474180000001, MethodInstance for main())])

julia> tmod, tpcs = pcmod.second;

julia> tmod
0.4204474180000001

julia> tpcs
1-element Vector{Tuple{Float64, Core.MethodInstance}}:
 (0.4204474180000001, MethodInstance for main())
```

0.42s of that time is due to `OptimizeMeFixed`, and `parcel` discovered a single MethodInstances to precompile, `main()`.

We could look at the other modules (packages) similarly.

## SnoopCompile.write

You can generate files that contain ready-to-use `precompile` directives using `SnoopCompile.write`:

```julia
julia> SnoopCompile.write("/tmp/precompiles_OptimizeMe", pcs)
Core: no precompile statements out of 0.000135179
Base: precompiled 0.026194226 out of 0.028383533000000002
Base.Ryu: precompiled 0.15733664599999997 out of 0.15733664599999997
Main.OptimizeMeFixed: precompiled 0.4204474180000001 out of 0.4204474180000001
```

You'll now find a directory `/tmp/precompiles_OptimizeMe`, and inside you'll find three files, for `Base`, `Base.Ryu`, and `OptimizeMeFixed`, respectively.
The contents of the last of these should be recognizable:

```julia
function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    Base.precompile(Tuple{typeof(main)})   # time: 0.4204474
end
```

The first `ccall` line ensures we only pay the cost of running these `precompile` directives if we're building the package; this is relevant mostly if you're running Julia with `--compiled-modules=no`, which can be a convenient way to disable precompilation and examine packages in their "native state."
(It would also matter if you've set `__precompile__(false)` at the top of your module, but if so why are you reading this?)

This file is ready to be moved into the `OptimizeMe` repository and `include`d into your module definition.
Since we added `warmup` manually, you could consider moving `precompile(warmup, ())` into this function.

You might also consider submitting some of the other files (or their `precompile` directives) to the packages you depend on.
In some cases, the specific argument type combinations may be too "niche" to be worth specializing; one such case is found here, a `show` method for `Tuple{String, Int64}` for `Base`.
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
  3.159908 seconds (10.63 M allocations: 582.091 MiB, 5.19% gc time, 99.67% compilation time)
```

versus

```julia
julia> @time (using OptimizeMeFixed; OptimizeMeFixed.main())
3.14 is great
2.718 is jealous
⋮
 Object x: 7
  1.840034 seconds (5.38 M allocations: 289.402 MiB, 5.03% gc time, 96.70% compilation time)
```

We've cut down on the latency by nearly a factor of two.
Moreover, if Julia someday caches generated code, we're well-prepared to capitalize on the benefits, because the same improvements in "code ownership" are almost certain to pay dividends there too.

If you inspect the results, you may sometimes suffer a few disappointments: some methods that we expected to precompile don't "take."
At the moment there appears to be a small subset of methods that fail to precompile, and the reasons are not yet widely understood.
At present, the best advice seems to be to comment-out any precompile directives that don't "take," since otherwise they increase the build time for the package without material benefit.
These failures may be addressed in future versions of Julia.
It's also worth appreciating how much we have succeeded in reducing latency, with the awareness that we may be able to get even greater benefit in the future.

## Summary

`@snoop_inference` collects enough data to learn which methods are triggering inference, how heavily methods are being specialized, and so on.
Examining your code from the standpoint of inference and specialization may be unfamiliar at first, but like other aspects of package development (testing, documentation, and release compatibility management) it can lead to significant improvements in the quality-of-life for you and your users.
