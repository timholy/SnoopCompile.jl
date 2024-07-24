# Understanding SnoopCompile and Julia's compilation pipeline

Julia uses
[Just-in-time (JIT) compilation](https://en.wikipedia.org/wiki/Just-in-time_compilation) to
generate the code that runs on your CPU.
Broadly speaking, there are two major compilation steps: *inference* and *code generation*.
Inference is the process of determining the type of each object, which in turn
determines which specific methods get called; once type inference is complete,
code generation performs optimizations and ultimately generates the assembly
language (native code) used on CPUs.
Some aspects of this process are documented [here](https://docs.julialang.org/en/v1/devdocs/eval/).

Using code that has never been compiled requires that it first be JIT-compiled, and this contributes to the latency of using the package.
In some circumstances, you can cache (store) the results of compilation to files to
reduce the latency when your package is used. These files are the the `*.ji` and
`*.so` files that live in the `compiled` directory of your Julia depot, usually
located at `~/.julia/compiled`. However, if these files become large, loading
them can be another source for latency. Julia needs time both to load and
validate the cached compiled code. Minimizing the latency of using a package
involves focusing on caching the compilation of code that is both commonly used
and takes time to compile.

Caching code for later use is called *precompilation*. Julia has had some forms of precompilation almost since the very first packages. However, it was [Julia
1.9](https://julialang.org/blog/2023/04/julia-1.9-highlights/#caching_of_native_code) that first supported "complete" precompilation, including the ability to store native code in shared-library cache files.

SnoopCompile is designed to try to allow you to analyze the costs of JIT-compilation, identify
key bottlenecks that contribute to latency, and set up `precompile` directives to see whether
it produces measurable benefits.

## Package precompilation

When a package is precompiled, here's what happens under the hood:

- Julia loads all of the package's dependencies (the ones in the `[deps]` section of the `Project.toml` file), typically from precompile cache files
- Julia evaluates the source code (text files) that define the package module(s). Evaluating `function foo(args...) ... end` creates a new method `foo`. Note that:
  + the source code might also contain statements that create "data" (e.g., `const`s). In some cases this can lead to some subtle precompilation ["gotchas"](@ref running-during-pc)
  + the source code might also contain a precompile workload, which forces compilation and tracking of package methods.
- Julia iterates over the module contents and writes the *result* to disk. Note that the module contents might include compiled code, and if so it is written along with everything else to the cache file.

When Julia loads your package, it just loads the "snapshot" stored in the cache file: it does not re-evaluate the source-text files that defined your package! It is appropriate to think of the source files of your package as "build scripts" that create your module; once the "build scripts" are executed, it's the module itself that gets cached, and the job of the build scripts is done.
