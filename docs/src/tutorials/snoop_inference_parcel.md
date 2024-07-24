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
In cases where you have some that are not naively precompilable, they will include MethodInstances from higher up in the call tree.

Let's use `SnoopCompile.parcel` on our [`OptimizeMe`](@ref inferrability) demo:

```@repl parcel-inference
using SnoopCompileCore, SnoopCompile # here we need the SnoopCompile path for the next line (normally you should wait until after data collection is complete)
include(joinpath(pkgdir(SnoopCompile), "examples", "OptimizeMe.jl"))
tinf = @snoop_inference OptimizeMe.main();
ttot, pcs = SnoopCompile.parcel(tinf);
ttot
pcs
```

`ttot` shows the total amount of time spent on type-inference.
`parcel` discovered precompilable MethodInstances for four modules, `Core`, `Base.Multimedia`, `Base`, and `OptimizeMe` that might benefit from precompile directives.
These are listed in increasing order of inference time.

Let's look specifically at `OptimizeMeFixed`, since that's under our control:

```@repl parcel-inference
pcmod = pcs[end]
tmod, tpcs = pcmod.second;
tmod
tpcs
```

This indicates the amount of time spent specifically on `OptimizeMe`, plus the list of calls that could be precompiled in that module.

We could look at the other modules (packages) similarly.

## SnoopCompile.write

You can generate files that contain ready-to-use `precompile` directives using `SnoopCompile.write`:

```@repl parcel-inference
SnoopCompile.write("/tmp/precompiles_OptimizeMe", pcs)
```

You'll now find a directory `/tmp/precompiles_OptimizeMe`, and inside you'll find files for modules that could have precompile directives added manually.
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

You might also consider submitting some of the other files (or their `precompile` directives) to the packages you depend on.
