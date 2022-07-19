# SnoopCompile.jl

SnoopCompile "snoops" on the Julia compiler, causing it to record the
functions and argument types it's compiling.  From these lists of methods,
you can generate lists of `precompile` directives that may reduce the latency between
loading packages and using them to do "real work."

SnoopCompile can also detect and analyze *method cache invalidations*,
which occur when new method definitions alter dispatch in a way that forces Julia to discard previously-compiled code.
Any later usage of invalidated methods requires recompilation.
Invalidation can trigger a domino effect, in which all users of invalidated code also become invalidated, propagating all the way back to the top-level call.
When a source of invalidation can be identified and either eliminated or mitigated,
you can reduce the amount of work that the compiler needs to repeat and take better advantage of precompilation.

Finally, SnoopCompile interacts with other important diagnostics and debugging tools in the Julia ecosystem.
For example, the combination of SnoopCompile and [JET](https://github.com/aviatesk/JET.jl) allows you to analyze an entire call-chain for
potential errors; see the page on [JET integration](@ref JET) for more information.

## Background

Julia uses
[Just-in-time (JIT) compilation](https://en.wikipedia.org/wiki/Just-in-time_compilation) to
generate the code that runs on your CPU.
Broadly speaking, there are two major steps: *inference* and *code generation*.
Inference is the process of determining the type of each object, which in turn
determines which specific methods get called; once type inference is complete,
code generation performs optimizations and ultimately generates the assembly
language (native code) used on CPUs.
Some aspects of this process are documented [here](https://docs.julialang.org/en/v1/devdocs/eval/).

Every time you load a package in a fresh Julia session, the methods you use
need to be JIT-compiled, and this contributes to the latency of using the package.
In some circumstances, you can partially cache the results of compilation to a file
(the `*.ji` files that live in your `~/.julia/compiled` directory) to reduce the burden
when your package is used.
This is called *precompilation*.
Unfortunately, precompilation is not as comprehensive as one might hope.
Currently, Julia is only able to save inference results (not native code) in the
`*.ji` files, and thus precompilation only eliminates the time needed for type inference.
Moreover, there are some significant constraints that sometimes prevent Julia from
saving even the inference results--for example, currently you cannot cache inference results
for "top level" calls to methods defined in Julia or other packages, even if you are calling them
with types defined in your package.
Finally, what does get saved can sometimes be invalidated by loading other packages.

Despite these limitations, there are many cases where precompilation can substantially reduce
latency.
SnoopCompile is designed to try to allow you to analyze the costs of JIT-compilation, identify
key bottlenecks that contribute to latency, and set up `precompile` directives to see whether
it produces measurable benefits.

## Who should use this package

SnoopCompile is intended primarily for package *developers* who want to improve the
experience for their users.
Because the results of SnoopCompile are typically stored in the `*.ji` precompile files,
users automatically get the benefit of any latency reductions achieved by adding
`precompile` directives to the source code of your package.

[PackageCompiler](https://github.com/JuliaLang/PackageCompiler.jl) is an alternative
that *non-developer users* may want to consider for their own workflow.
It builds an entire system image (Julia + a set of selected packages) and caches both the
results of type inference and the native code.
Typically, PackageCompiler reduces latency more than just "plain" `precompile` directives.
However, PackageCompiler does have significant downsides, of which the largest is that
it is incompatible with package updates--any packages built into your system image
cannot be updated without rebuilding the entire system.
Particularly for people who develop or frequently update their packages, the downsides of
PackageCompiler may outweigh its benefits.

Finally, another alternative for reducing latency without any modifications
to package files is [Revise](https://github.com/timholy/Revise.jl).
It can be used in conjunction with SnoopCompile.

## Basic usage: SnoopPrecompile

The "SnoopCompile family" includes a very small package, `SnoopPrecompile` (which does not require `SnoopCompile` itself),
with which most packages can easily and effectively precompile code, particularly for Julia versions 1.8 and higher.
See the [SnoopPrecompile](@ref) documentation.

For many package developers, `SnoopPrecompile` may be all you need. In case of trouble (or if you want to check that
`SnoopPrecompile` did its job thoroughly), the rest of `SnoopCompile` provides more sophisticated diagnostics.

## [A note on Julia versions and the recommended workflow](@id workflow)

SnoopCompile is closely intertwined with Julia's own internals.
Some "data collection" and analysis features are available only on newer versions of Julia.
In particular, some of the most powerful tools were made possible through several additions made in Julia 1.6;
SnoopCompile just exposes these tools in convenient form.

If you're a developer looking to reduce the latency of your packages, you are *strongly*
encouraged to use SnoopCompile on Julia 1.6 or later. The fruits of your labors will often
reduce latency even for users of earlier Julia versions, but your ability to understand
what changes need to be made will be considerably enhanced by using the latest tools.

For developers who can use Julia 1.6+, the recommended sequence is:

1. Check for [invalidations](@ref), and if egregious make fixes before proceeding further
2. Record inference data with [`@snoopi_deep`](@ref). Analyze the data to:
    + adjust method specialization in your package or its dependencies (see [pgds](@ref))
    + fix problems in [inferrability](@ref)
    + add [precompilation](@ref)

Under 2, the first two sub-points can often be done at the same time; the last item is best done as a final step, because the specific
precompile directives needed depend on the state of your code, and a few fixes in specialization
and/or type inference can alter or even decrease the number of necessary precompile directives.

Although there are other tools within SnoopCompile available, most developers can probably stop after the steps above.
The documentation will describe the tools in this order, followed by descriptions of additional and older tools.
