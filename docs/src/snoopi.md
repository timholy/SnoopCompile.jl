# [Snooping on inference: `@snoopi`](@id macro-snoopi)

If you can't use `@snoop_inference` due to Julia version constraints, the most useful choice is `@snoopi`, which is available on Julia 1.2 or higher.

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
(defined for `Array{Float16,1}`). This is because precompilation requires the
types of the arguments to specialize the code appropriately.

The information obtained from `@snoopi` can be used in several ways, primarily to reduce latency during usage of your package:

- to help you understand which calls take the most inference time
- to help you write `precompile` directives that run inference on specific calls during package precompilation, so that you don't pay this cost repeatedly each time you use the package
- to help you identify inference problems that prevent successful or comprehensive precompilation

If you're starting a project to try to reduce latency in your package, broadly speaking there are two paths you can take:

1. you can use SnoopCompile, perhaps together with [CompileBot](https://github.com/aminya/CompileBot.jl),
   to automatically generate lists of precompile directives that may reduce latency;
2. you can use SnoopCompile primarily as an analysis tool, and then intervene manually to reduce latency.

Beginners often leap at option 1, but experience shows there are good reasons to consider option 2.
To avoid introducing too much complexity early on, we'll defer this discussion to the end of this page, but readers who are serious about reducing latency should be sure to read [Understanding precompilation and its limitations](@ref).

!!! note
    Because invalidations can prevent effective precompilation, developers analyzing their
    packages with `@snoopi` are encouraged to use Julia versions (1.6 and higher) that have a lower risk
    of invalidations in Base and the standard library.

## [Precompile scripts](@id pcscripts)

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
    the speed of your machine. Moreover, if FixedPointNumbers has
    already precompiled these method and type combinations---perhaps
    by incorporating a precompile file produced by SnoopCompile---then
    those methods will be absent.  For packages whose precompile
    directives are executed only when `ccall(:jl_generating_output,
    Cint, ()) == 1`, you can start Julia with `--compiled-modules=no`
    to disable them.  Alternatively, you can `dev` the package and
    comment them out.

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
    you can check that `precompile` returns `true` and otherwise issue a warning.
    By default, [`SnoopCompile.write`](@ref) generates
    a macro, `@warnpcfail`, and you can use it by
    changing `precompile(args...)` to `@warnpcfail precompile(args...)`.


If you find that some precompile directives are
ineffective (they appear in a new `@snoopi` despite being precompiled) and their
inference time is substantial, sometimes a bit of manual investigation of the callees
can lead to insights. For example, you might be able to introduce a precompile in a
dependent package that can mitigate the total time.
(`@snoop_inference` makes the analysis and resolution of these issues more straightforward.)

!!! tip
    For packages that support just Julia 1.6 and higher, you may be able to slim down the precompile file by
    adding `has_bodyfunction=true` to the arguments for `parcel`.
    This setting applies for all packges in `inf_timing`, so you may need to call `parcel` twice (with both `false` and `true`) and select the appropriate precompile file for each package.

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


## Understanding precompilation and its limitations

Suppose your package includes the following method:

```julia
"""
    idx = index_midsum(a)

Return the index of the first item more than "halfway to the cumulative sum,"
meaning the smallest integer so that `sum(a[begin:idx]) >= sum(a)/2`.
"""
function index_midsum(a::AbstractVector)
    ca = cumsum(vcat(0, a))   # cumulative sum of items in a, starting from 0
    s = ca[end]               # the sum of all elements
    return findfirst(x->x >= s/2, ca) - 1  # compensate for inserting 0
end
```
Now, suppose that you'd like to reduce latency in using this method, and you know that an important use case is when `a` is a `Vector{Int}`.
Therefore, you might precompile it:

```julia
julia> precompile(index_midsum, (Vector{Int},))
true
```
This will cause Julia to infer this method for the given argument types. If you add such statements to your package, it potentially saves your users from having to wait for it to be inferred each time they use your package.

!!! note
    The `true` indicates that Julia was successfully able to find a method supporting this signature and precompile it.
    See the note about `@warnpcfail` above for ways to exploit this in your package.


But if you execute these lines in the REPL, and then check how well it worked, you might see something like the following:
```julia
julia> using SnoopCompile

julia> tinf = @snoopi index_midsum([1,2,3,4,100])
3-element Vector{Tuple{Float64, Core.MethodInstance}}:
 (0.00048613548278808594, MethodInstance for cat_similar(::Int64, ::Type, ::Tuple{Int64}))
 (0.010090827941894531, MethodInstance for (::Base.var"#cat_t##kw")(::NamedTuple{(:dims,), Tuple{Val{1}}}, ::typeof(Base.cat_t), ::Type{Int64}, ::Int64, ::Vararg{Any, N} where N))
 (0.016659975051879883, MethodInstance for __cat(::Vector{Int64}, ::Tuple{Int64}, ::Tuple{Bool}, ::Int64, ::Vararg{Any, N} where N))
```
Even though we'd already said `precompile(index_midsum, (Vector{Int},))` in this session, somehow we needed *more* inference of various concatenation methods.
Why does this happen?
A detailed investigation (e.g., using [Cthulhu](https://github.com/JuliaDebug/Cthulhu.jl) or `@code_warntype`) would reveal that `vcat(0, a)` is not inferrable "all the way down," and hence the `precompile` directive couldn't predict everything that was going to be needed.

No problem, you say: let's just precompile those methods too. The most expensive is the last one. You might not know where `__cat` is defined, but you can find out with
```julia
julia> mi = tinf[end][2]    # get the MethodInstance
MethodInstance for __cat(::Vector{Int64}, ::Tuple{Int64}, ::Tuple{Bool}, ::Int64, ::Vararg{Any, N} where N)

julia> mi.def               # get the Method
__cat(A, shape::Tuple{Vararg{Int64, M}}, catdims, X...) where M in Base at abstractarray.jl:1599

julia> mi.def.module        # which module was this method defined in?
Base
```

!!! note
    When using `@snoopi` you might sometimes see entries like
    `MethodInstance for (::SomeModule.var"#10#12"{SomeType})(::AnotherModule.AnotherType)`.
    These typically correspond to closures/anonymous functions defined with `->` or `do` blocks,
    but it may not be immediately obvious where these come from.
    `mi.def` will show you the file/line number that these are defined on.
    You can either convert them into named functions to make them easier to precompile,
    or you can fix inference problems that prevent automatic precompilation (as illustrated below).

Armed with this knowledge, let's start a fresh session (so that nothing is precompiled yet), and in addition to defining `index_midsum` and precompiling it, we also execute

```julia
julia> precompile(Base.__cat, (Vector{Int64}, Tuple{Int64}, Tuple{Bool}, Int, Vararg{Any, N} where N))
true
```

Now if you try that `tinf = @snoopi index_midsum([1,2,3,4,100])` line, you'll see that the `__cat` call is omitted, suggesting success.

However, if you copy both `precompile` directives into your package source files and then check it with `@snoopi` again,
you may be in for a rude surprise: the `__cat` precompile directive doesn't "work."
That turns out to be because your package doesn't "own" that `__cat` method--the module is `Base` rather than `YourPackage`--and because inference cannot determine that it's needed by by `index_midsum(::Vector{Int})`, Julia doesn't know which `*.ji` file to use to
store its precompiled form.

How to fix this?
Fundamentally, the problem is that `vcat` call: if we can write `index_midsum` in a way so that inference succeeds, then all these problems go away.
(You can use `ascend(mi)`, with Cthulhu.jl, where `mi` was obtained above, to discover that `__cat` gets called from `vcat`. See [`Cthulhu.ascend`](@ref ascend-itrig) for more information.)
It turns out that `vcat` is inferrable if all the arguments have the same type, so just changing `vcat(0, a)` to `vcat([zero(eltype(a))], a)` fixes the problem.
(Alternatively, you could make a copy and then use `pushfirst!`.)
In a fresh Julia session:

```julia
function index_midsum(a::AbstractVector)
    ca = cumsum(vcat([zero(eltype(a))], a))   # cumulative sum of items in a, starting from 0
    s = ca[end]               # the sum of all elements
    return findfirst(x->x >= s/2, ca) - 1  # compensate for inserting 0
end

julia> precompile(index_midsum, (Vector{Int},))
true

julia> using SnoopCompile

julia> tinf = @snoopi index_midsum([1,2,3,4,100])
Tuple{Float64, Core.MethodInstance}[]
```

Tada! No additional inference was needed, ensuring that your users will not suffer any latency due to type-inference of this particular method/argument combination.
In addition to identifing a call deserving of precompilation, `@snoopi` helped us identify a weakness in its implementation.
Fixing that weakness reduced latency, made the code more resistant to invalidation, and may improve runtime performance.

In other cases, manual inspection of the results from `@snoopi` may lead you in a different direction: you may discover that a huge number of specializations are being created for a method that doesn't need them.
Typical examples are methods that take types or functions as inputs: for example, there is no reason to recompile `methods(f)` for each separate `f`.
In such cases, by far your best option is to add `@nospecialize` annotations to one or more of the arguments of that method. Such changes can have dramatic impact on the latency of your package.

The ability to make interventions like these--which can both reduce latency and improve runtime speed--is a major reason to consider `@snoopi` primarily as an analysis tool rather than just a utility to blindly generate lists of precompile directives.
