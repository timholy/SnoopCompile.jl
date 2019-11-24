# SnoopCompile.jl

SnoopCompile "snoops" on the Julia compiler, causing it to record the
functions and argument types it's compiling.  From these lists of methods,
you can generate lists of `precompile` directives that may reduce the latency between
loading packages and using them to do "real work."

## Background

Julia uses
[Just-in-time (JIT) compilation](https://en.wikipedia.org/wiki/Just-in-time_compilation) to
generate the code that runs on your CPU.
Broadly speaking, there are two major steps: *inference* and *code generation*.
Inference is the process of determining the type of each object, which in turn
determines which specific methods get called; once type inference is complete,
code generation performs optimizations and ultimately generates the assembly
language (native code) used on CPUs.
Some aspects of this process are documented [here](https://docs.julialang.org/en/latest/devdocs/eval).

Every time you load a package in a fresh Julia session, the methods you use
need to be JIT-compiled, and this contributes to the latency of using the package.
In some circumstances, you can save some of the work to reduce the burden next time.
This is called *precompilation*.
Unfortunately, precompilation is not as comprehensive as one might hope.
Currently, Julia is only capable of saving inference results (not native code) in the
`*.ji` files that are the result of precompilation.
Moreover, there are some significant constraints that sometimes prevent Julia from
saving even the inference results;
and finally, what does get saved can sometimes be invalidated if later packages
provide more specific methods that supersede some of the calls in the precompiled methods.

Despite these limitations, there are cases where precompilation can substantially reduce
latency.
SnoopCompile is designed to try to make it easy to try precompilation to see whether
it produces measurable benefits.

## Who should use this package

SnoopCompile is intended primarily for package *developers* who want to improve the
experience for their users.
Because the results of SnoopCompile are typically stored in the `*.ji` precompile files,
anyone can take advantage of the reduced latency.

[PackageCompiler](https://github.com/JuliaLang/PackageCompiler.jl) is an alternative
that *non-developer users* may want to consider for their own workflow.
It performs more thorough precompilation than the "standard" usage of SnoopCompile,
although one can achieve a similar effect by creating [`userimg.jl` files](@ref userimg).
However, the cost is vastly increased build times, which for package developers is
unlikely to be productive.

Finally, another alternative that reduces latency without any modifications
to package files is [Revise](https://github.com/timholy/Revise.jl).
It can be used in conjunction with SnoopCompile.
