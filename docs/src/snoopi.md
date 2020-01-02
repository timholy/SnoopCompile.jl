# Snooping on inference: `@snoopi`

The most useful tool is a macro, `@snoopi`, which is only available on Julia 1.2 or higher.

Julia can cache inference results, so you can use `@snoopi` to generate `precompile`
directives for your package. Executing these directives when the package is compiled
may reduce compilation (inference) time when the package is used.

Here's a quick demo:

```julia
using SnoopCompile

a = rand(Float16, 5)

julia> inf_timing = @snoopi sum(a)
1-element Array{Tuple{Float64,Core.MethodInstance},1}:
 (0.011293888092041016, MethodInstance for sum(::Array{Float16,1}))
```

We defined the argument `a`, and then called `sum(a)` while "snooping" on inference.
(The `i` in `@snoopi` means "inference.")
The return is a list of "top level" methods that got compiled, together with the amount of
time spent on inference.
In this case it was just a single method, which required approximately 11ms of inference time.
(Inferring `sum` required inferring all the methods that it calls, but these are
subsumed into the top level inference of `sum` itself.)
Note that the method that got called,

```julia
julia> @which sum(a)
sum(a::AbstractArray) in Base at reducedim.jl:652
```

is much more general (i.e., defined for `AbstractArray`) than the `MethodInstance`
(defined for `Array{Float16,1}`). This is because precompilation happens only for
concrete objects passed as arguments.

## Precompile scripts

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
2-element Array{Tuple{Float64,Core.MethodInstance},1}:
 (0.03108978271484375, MethodInstance for *(::Normed{UInt8,8}, ::Normed{UInt8,8}))
 (0.04189491271972656, MethodInstance for Normed{UInt8,8}(::Float64))             
```

Here, note the `tmin=0.01`, which causes any methods that take less than 10ms of inference
time to be discarded.

!!! note
    If you're testing this, you might get different results depending on
    the speed of your machine. Moreover, if FixedPointNumbers has already precompiled
    these method and type combinations---perhaps by incorporating a precompile file
    produced by SnoopCompile---then those methods will be absent.
    If you want to try this example, `dev FixedPointNumbers` and disable any
    `_precompile_()` call you find.

You can inspect these results and write your own precompile file, or use the automated
tools provided by SnoopCompile.

## [Producing precompile directives automatically](@id auto)

You can take the output of `@snoopi` and "parcel" it into packages:

```julia
julia> pc = SnoopCompile.parcel(inf_timing)
Dict{Symbol,Array{String,1}} with 1 entry:
  :FixedPointNumbers => ["precompile(Tuple{typeof(*),Normed{UInt8,8},Normed{UInt8,8}})", "precompile(Tuple{Type{Normed{UInt8,8}},Float64})"]
```

This splits the calls up into a dictionary, `pc`, indexed by the package which "owns"
each call.
(In this case there is only one, `FixedPointNumbers`, but in more complex cases there may
be several.) You can then write the results to files:

```julia
julia> SnoopCompile.write("/tmp/precompile", pc)
```

If you look in the `/tmp/precompile` directory, you'll see one or more
files, named by their parent package, that may be suitable for `include`ing into the package.
In this case:

```
/tmp/precompile$ cat precompile_FixedPointNumbers.jl
function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    precompile(Tuple{typeof(*),Normed{UInt8,8},Normed{UInt8,8}})
    precompile(Tuple{Type{Normed{UInt8,8}},Float64})
end
```

If you copy this file to a `precompile.jl` file in the `src` directory,
you can incorporate it into the package like this:

```julia
module FixedPointNumbers

# All the usual commands that define the module go here

# ... followed by:

include("precompile.jl")
_precompile_()

end # module FixedPointNumbers
```

The listed method/type combinations should have their inference results cached.
Load the package once to precompile it, and then in a fresh Julia session try this:

```julia
julia> using SnoopCompile

julia> inf_timing = @snoopi tmin=0.01 include("snoopfpn.jl")
0-element Array{Tuple{Float64,Core.MethodInstance},1}
```

The fact that no methods were returned is a sign of success: Julia didn't need to call
inference on those methods, because it used the inference results from the cache file.

!!! note
    Sometimes, `@snoopi` will show method & type combinations that you precompiled.
    This is a sign that despite your attempts, Julia declined to cache the inference
    results for those methods.
    You can either delete those directives from the precompile file, or hope that
    they will become useful in a future version of Julia.
    Note that having many "useless" precompile directives can slow down precompilation.

!!! note
    As you develop your package, it's possible you'll modify or delete some of the
    methods that appear in your `"precompile.jl"` file.
    This will *not* result in an error; by default `precompile` fails silently.
    If you want to be certain that your precompile directives don't go stale,
    preface each with an `@assert`.
    Note that this forces you to update your precompile directives as you modify your package,
    which may or may not be desirable.

If you find that some precompile directives are
ineffective (they appear in a new `@snoopi` despite being precompiled) and their
inference time is substantial, sometimes a bit of manual investigation of the callees
can lead to insights. For example, you might be able to introduce a precompile in a
dependent package that can mitigate the total time.

## Producing precompile directives manually

While this "automated" approach is often useful, sometimes it makes more sense to
inspect the results and write your own precompile directives.
For example, for FixedPointNumbers a more elegant and comprehensive precompile file
might be

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

## Analyzing omitted methods

There are some method signatures that cannot be precompiled.
For example, suppose you have two packages, `A` and `B`, that are independent of one another.
Then `A.f([B.Object(1)])` cannot be precompiled, because `A` does not know about `B.Object`,
and `B` does not know about `A.f`, unless both `A` and `B` get included into a third package.

Such problematic method signatures are removed automatically.
If you want to be informed about these removals, you can use Julia's logging framework
while running `parcel`:

```
julia> using Base.CoreLogging

julia> logger = SimpleLogger(IOBuffer(), CoreLogging.Debug);

julia> pc = with_logger(logger) do
           SnoopCompile.parcel(inf_timing)
       end

julia> msgs = String(take!(logger.stream))
```

The omitted method signatures will be logged to the string `msgs`.
