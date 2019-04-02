# SnoopCompile

[![Build Status](https://travis-ci.org/timholy/SnoopCompile.jl.svg?branch=master)](https://travis-ci.org/timholy/SnoopCompile.jl)

SnoopCompile "snoops" on the Julia compiler, getting it to log the
functions and argument-types it's compiling.  By parsing the log file,
you can learn which functions are being precompiled, and even how long
each one takes to compile.  You can use the package to generate
"precompile lists" that reduce the amount of time needed for JIT
compilation in packages.

## Usage

### Snooping on inference

Currently precompilation only saves inferred code; consequently, the time spent on type inference
is probably the most relevant concern. To learn how much time is spent on each method instance
when executing a command `cmd`, do something like the following (note: requires Julia 1.2 or higher):

```julia
using SnoopCompile

a = rand(Float16, 5)
inf_timing = @snoopi tmin=0.01 sum(a)
```

### Snooping on the compiler

The easiest way to describe SnoopCompile is to show a snoop script, in this case for the `ColorTypes` package:

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

After the conclusion of this script, the `"/tmp/precompile"` folder will contain a number of `*.jl` files, organized by package.
For each package, you could copy its corresponding `*.jl` file into the package's `src/` directory
and `include` it into the package:

```jl
module SomeModule

# All the usual commands that define the module go here

# ... followed by:

include("precompile.jl")
_precompile_()

end # module SomeModule
```

There's a more complete example illustrating potential options in the `examples/` directory.

### Additional flags

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

## `userimg.jl`

Currently, precompilation does not cache functions from other modules; as a consequence, your speedup in execution time might be smaller than you'd like. In such cases, one strategy is to generate a script for your `base/userimg.jl` file and build the packages (with precompiles) into julia itself.  Simply append/replace the last two lines of the above script with

```jl
# Use these two lines if you want to add to your userimg.jl
pc = SnoopCompile.format_userimg(reverse!(data[2]))
SnoopCompile.write("/tmp/userimg_Images.jl", pc)
```

**Users are warned that there are substantial negatives associated with relying on a `userimg.jl` script**:
- Your julia build times become very long
- `Pkg.update()` will have no effect on packages that you've built into julia until you next recompile julia itself. Consequently, you may not get the benefit of enhancements or bug fixes.
- For a package that you sometimes develop, this strategy is very inefficient, because testing a change means rebuilding Julia as well as your package.
