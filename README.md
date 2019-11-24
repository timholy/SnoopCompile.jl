# SnoopCompile

[![Build Status](https://travis-ci.org/timholy/SnoopCompile.jl.svg?branch=master)](https://travis-ci.org/timholy/SnoopCompile.jl)

SnoopCompile "snoops" on the Julia compiler, getting it to log the
functions and argument-types it's compiling.  By parsing the log file,
you can learn which functions are being precompiled, and even how long
each one takes to compile.  You can use the package to generate
"precompile lists" that reduce the amount of time needed for JIT
compilation in packages.

## Usage

### Snooping on inference (recommended)

Currently precompilation only saves inferred code; consequently, the time spent on type inference
is probably the most relevant concern. To learn how much time is spent on each method instance
when executing a command `cmd`, do something like the following (note: requires Julia 1.2 or higher):

```julia
using SnoopCompile

a = rand(Float16, 5)

julia> inf_timing = @snoopi tmin=0.01 sum(a)
1-element Array{Tuple{Float64,Core.MethodInstance},1}:
 (0.011293888092041016, MethodInstance for sum(::Array{Float16,1}))
```

Here, we filtered out methods that took less than 10ms to compile via `tmin=0.01`.
We can see that only one method took longer than this (and if your machine is faster than
mine, `inf_timing` might even be empty with these settings).
You can see the specific `MethodInstance` that got compiled.
Note that

```julia
julia> @which sum(a)
sum(a::AbstractArray) in Base at reducedim.jl:652
```

indicates that the method is much more general (i.e., defined for `AbstractArray`)
than the instance (defined for `Array{Float16,1}`); precompilation works on the concrete
types of the objects passed as arguments.

You can use `@snoopi` to come up with a list of precompile-worthy functions.
A recommended approach is to write a script that "exercises" the functionality
you'd like to precompile.
One option is to use your package's `"runtests.jl"` file, or you can write a custom
script for this purpose.
Here's an example for the
[FixedPointNumbers package](https://github.com/JuliaMath/FixedPointNumbers.jl):

```
using FixedPointNumbers

x = N0f8(0.2)
y = x + x
y = x - x
y = x*x
y = x/x
y = Float32(x)
y = Float64(x)
y = 0.3*x
y = x*0.3
y = 2*x
y = x*2
y = x/15
y = x/8.0
```

Save this as a file `"snoopfpn.jl"` and navigate at the Julia REPL to that directory,
and then do

```julia
julia> using SnoopCompile

julia> inf_timing = @snoopi tmin=0.01 include("snoopfpn.jl")
3-element Array{Tuple{Float64,Core.MethodInstance},1}:
 (0.016037940979003906, MethodInstance for *(::Float64, ::Normed{UInt8,8}))        
 (0.028206825256347656, MethodInstance for *(::Normed{UInt8,8}, ::Normed{UInt8,8}))
 (0.0369410514831543, MethodInstance for Normed{UInt8,8}(::Float64))               
```

SnoopCompile contains utilities that for generating precompile files that can be `include`d into
package(s):

```julia
 julia> pc = SnoopCompile.parcel(inf_timing)
 Dict{Symbol,Array{String,1}} with 1 entry:
   :FixedPointNumbers => ["precompile(Tuple{typeof(*),Float64,Normed{UInt8,8}})", "precompile(Tuple{typeof(*),Normed{UInt8,8},Normed{UInt8,8}})", "precompile(Tuple{Type{Normed{UInt8,8}},Float64})"]

 julia> SnoopCompile.write("/tmp/precompile", pc)
```

This splits the calls up into a dictionary, `pc`, indexed by the package which "owns"
each call.
(In this case there is only one, `FixedPointNumbers`, but in more complex cases there may
be several.) If you then look in the `/tmp/precompile` directory, you'll see one or more
files, named by their parent package, that may be suitable for `include`ing into your
module definition(s).
These may or may not reduce the time for your package to execute similar operations.

While this "automated" approach is often useful, sometimes it makes more sense to
inspect the results and write your own precompile directives.
For example, for FixedPointNumbers a more elegant precompile file could be

```julia
function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    for T in (N0f8, N0f16)      # Normed types we want to support
        for f in (+, -, *, /)   # operations we want to support
            precompile(Tuple{typeof(f),T,T})
            for S in (Float32, Float64, Int)   # other number types we want to support
                precompile(Tuple{typeof(f),T,S})
                precompile(Tuple{typeof(f),S,T})
            end
        end
        for S in (Float32, Float64)
            precompile(Tuple{Type{T},S})
            precompile(Tuple{Type{S},T})
        end
    end
end
```

This covers `+`, `-`, `*`, `/`, and conversion for various combinations of types.
The results from `@snoopi` can suggest method/type combinations that might be useful to
precompile, but often you can generalize its suggestions in useful ways.

If you `include` a precompile file into your package definition and then run the same
`@snoopi` command again, hopefully it will omit many of the MethodInstances
you obtained previously.
This is a sign of success.
Unfortunately, at present Julia has some significant limitations in terms of how
extensively it can cache inference results, so you may not see as many of these
methods "disappear" as you might hope.

**NOTE**: if you later modify your code so that some of the methods no longer
exist, `precompile` will *not* throw an error; it will instead fail silently.
If you want to be certain that your precompile directives don't go stale,
preface each with an `@assert`.
Note that this forces you to update your precompile directives as you modify your package,
which may or may not be desirable.

### Snooping on the compiler

SnoopCompile can also snoop on native code generation using a macro `@snoopc`,
and thereby also determine what methods are being compiled.
Note that native code is not cached, so this approach may not prioritize the most
most useful methods in the same way that `@snoopi` does.

Here's let's demonstrate `@snoopc` with a snoop script, in this case for the `ColorTypes` package:

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
