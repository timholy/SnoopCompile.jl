# Snooping on code generation: `@snoopc`

`@snoopc` has the advantage of working on any modern version of Julia.
It "snoops" on the code-generation phase of compilation (the 'c' is a reference to
code-generation).
Note that while native code is not cached, it nevertheless reveals
which methods are being compiled.

Note that unlike `@snoopi`, `@snoopc` will generate all methods, not just the top-level
methods that trigger compilation.
(It is redundant to precompile dependent methods, but neither is it harmful.)
It is also worth noting that `@snoopc` requires "spinning up" a new Julia process,
and so it is a bit slower than `@snoopi`.

Let's demonstrate `@snoopc` with a snoop script, in this case for the `ColorTypes` package:

```julia
using SnoopCompile

### Log the compiles
# This only needs to be run once (to generate "/tmp/colortypes_compiles.log")

SnoopCompile.@snoopc "/tmp/colortypes_compiles.log" begin
    using ColorTypes, Pkg
    include(joinpath(dirname(dirname(pathof(ColorTypes))), "test", "runtests.jl"))
end

### Parse the compiles and generate precompilation scripts
# This can be run repeatedly to tweak the scripts

data = SnoopCompile.read("/tmp/colortypes_compiles.log")

pc = SnoopCompile.parcel(reverse!(data[2]))
SnoopCompile.write("/tmp/precompile", pc)
```

As with `@snoopi`, the `"/tmp/precompile"` folder will now contain a number of `*.jl` files,
organized by package.
For each package, you could copy its corresponding `*.jl` file into the package's `src/` directory
and `include` it into the package as described for [`@snoopi`](@ref auto).

There are more complete example illustrating potential options in the `examples/` directory.

## Additional flags

When calling the `@snoopc` macro, a new julia process is spawned using the function `Base.julia_cmd()`.
Advanced users may want to tweak the flags passed to this process to suit specific needs.
This can be done by passing an array of flags of the form `["--flag1", "--flag2"]` as the first argument to the `@snoop` macro.
For instance, if you want to pass the `--project=/path/to/dir` flag to the process, to cause the julia process to load the project specified by the path, a snoop script may look like:
```julia
using SnoopCompile

SnoopCompile.@snoopc ["--project=/path/to/dir"] "/tmp/compiles.csv" begin
    # ... statement to snoop on
end

# ... processing the precompile statements
```
