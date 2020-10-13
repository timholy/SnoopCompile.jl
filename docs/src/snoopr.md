# Snooping on and fixing invalidations: `@snoopr`

!!! note
    `@snoopr` is available on `Julia 1.6.0-DEV.154` or above, but the results can be relevant for all Julia versions.

## Recording invalidations

```@meta
DocTestFilters = r"(REPL\[\d+\]|none):\d+"
DocTestSetup = quote
    using SnoopCompile
end
```

Invalidations occur when there is a danger that new methods would supersede older methods in previously-compiled code.

To record the invalidations caused by defining new methods, use `@snoopr`.
`@snoopr` is exported by SnoopCompile, but the recommended approach is to record invalidations using the minimalistic `SnoopCompileCore` package, and then load `SnoopCompile` to do the analysis:

```julia
using SnoopCompileCore
invalidations = @snoopr begin
    # package loads and/or method definitions that might invalidate other code
end
using SnoopCompile   # now that we've collected the data, load the complete package to analyze the results
```

!!! note
    `SnoopCompileCore` was split out from `SnoopCompile` to reduce the risk of invalidations from loading `SnoopCompile` itself.
    Once a MethodInstance gets invalidated, it doesn't show up in future `@snoopr` results, so anything that
    gets invalidated in order to provide `@snoopr` would be omitted from the results.
    `SnoopCompileCore` is a very small package with no dependencies and which avoids extending any of Julia's own functions,
    so it cannot invalidate any other code.

## Analyzing invalidations

### A first example

We'll walk through this process with the following example:

```jldoctest invalidations
julia> f(::Real) = 1;

julia> callf(container) = f(container[1]);

julia> call2f(container) = callf(container);
```

Because code doesn't get compiled until it gets run, and invalidations only affect compiled code, let's run this with different container types:

```jldoctest invalidations
julia> c64  = [1.0]; c32 = [1.0f0]; cabs = AbstractFloat[1.0];

julia> call2f(c64)
1

julia> call2f(c32)
1

julia> call2f(cabs)
1
```

!!! warning
    If you're following along, be sure you actually execute these methods, or you won't obtain the results below.

Now we'll define a new `f` method, one specialized for `Float64`.
So we can see the consequences for the compiled code, we'll make this definition while snooping on the compiler with `@snoopr`:

```jldoctest invalidations
julia> using SnoopCompileCore

julia> invalidations = @snoopr f(::Float64) = 2;

julia> using SnoopCompile
```

The simplest thing we can do is list or count invalidations:

```jldoctest invalidations
julia> length(uinvalidated(invalidations))  # collect the unique MethodInstances & count them
6
```

The length of this set is your simplest insight into the extent of invalidations triggered by this method definition.

If you want to fix invalidations, it's crucial to know *why* certain MethodInstances were invalidated.
For that, it's best to use a tree structure, in which children are invalidated because their parents get invalidated:

```jldoctest invalidations
julia> trees = invalidation_trees(invalidations)
1-element Vector{SnoopCompile.MethodInvalidations}:
 inserting f(::Float64) in Main at REPL[9]:1 invalidated:
   backedges: 1: superseding f(::Real) in Main at REPL[2]:1 with MethodInstance for f(::Float64) (2 children)
              2: superseding f(::Real) in Main at REPL[2]:1 with MethodInstance for f(::AbstractFloat) (2 children)
```

The output, `trees`, is a vector of `MethodInvalidations`, a data type defined in `SnoopCompile`; each of these is the set of invalidations triggered by a particular method definition.
In this case, we only defined one method, so we can get at most one `MethodInvalidation`.
`@snoopr using SomePkg` might result in a list of such objects, each connected to a particular method defined in a particular package (either `SomePkg` itself or one of its dependencies).

In this case, "`inserting f(::Float64)`" indicates that we added a method with signature `f(::Float64)`, and that this method triggered invalidations.
(Invalidations can also be triggered by method deletion, although this should not happen in typical usage.)
Next, notice the `backedges` line, and the fact that there are two items listed for it.
This indicates that there were two proximal triggers for the invalidation, both of which superseded the method `f(::Real)`.
One of these had been compiled specifically for `Float64`, due to our `call2f(c64)`.
The other had been compiled specifically for `AbstractFloat`, due to our `call2f(cabs)`.

You can look at these invalidation trees in greater detail:

```jldoctest invalidations
julia> method_invalidations = trees[1];    # invalidations stemming from a single method

julia> root = method_invalidations.backedges[1]  # get the first triggered invalidation
MethodInstance for f(::Float64) at depth 0 with 2 children

julia> show(root)
MethodInstance for f(::Float64) (2 children)
 MethodInstance for callf(::Vector{Float64}) (1 children)
 ⋮

julia> show(root; minchildren=0)
MethodInstance for f(::Float64) (2 children)
 MethodInstance for callf(::Vector{Float64}) (1 children)
  MethodInstance for call2f(::Vector{Float64}) (0 children)
```

The indentation here reveals that `call2f` called `callf` which called `f`,
and shows the entire "chain" of invalidations triggered by this method definition.
Examining `root2 = method_invalidations.backedges[2]` yields similar results, but for `Vector{AbstractFloat}`.

### `mt_backedges` invalidations

`MethodInvalidations` can have a second field, `mt_backedges`.
These are invalidations triggered via the `MethodTable` for a particular function.
When extracting `mt_backedges`, in addition to a root `MethodInstance` these also indicate a particular signature that triggered the invalidation.
We can illustrate this by returning to the `call2f` example above:

```jldoctest invalidations
julia> call2f(["hello"])
ERROR: MethodError: no method matching f(::String)
[...]

julia> invalidations = @snoopr f(::AbstractString) = 2;

julia> trees = invalidation_trees(invalidations)
1-element Vector{SnoopCompile.MethodInvalidations}:
 inserting f(::AbstractString) in Main at REPL[6]:1 invalidated:
   mt_backedges: 1: signature Tuple{typeof(f), String} triggered MethodInstance for callf(::Vector{String}) (1 children)


julia> sig, root = trees[1].mt_backedges[end];

julia> sig
Tuple{typeof(f), String}

julia> root
MethodInstance for callf(::Vector{String}) at depth 0 with 1 children
```

You can see that the invalidating signature, `f(::String)`, is more specific than the signature of the defined method, but that it is what was minimally needed by `callf(::Vector{String})`.

`mt_backedges` invalidations often reflect "unhandled" conditions in methods that have already been compiled.

### A more complex example

The structure of these trees can be considerably more complicated. For example, if `callf`
also got called by some other method, and that method had also been executed (forcing it to be compiled),
then `callf` would have multiple children.
This is often seen with more complex, real-world tests.
As a medium-complexity example, try the following:

```julia
julia> using Revise

julia> using SnoopCompileCore

julia> invalidations = @snoopr using FillArrays;

julia> using SnoopCompile

julia> trees = invalidation_trees(invalidations)
3-element Vector{SnoopCompile.MethodInvalidations}:
 inserting all(f::Function, x::FillArrays.AbstractFill) in FillArrays at /home/tim/.julia/packages/FillArrays/NjFh2/src/FillArrays.jl:556 invalidated:
   backedges: 1: superseding all(f::Function, a::AbstractArray; dims) in Base at reducedim.jl:880 with MethodInstance for all(::Base.var"#388#389"{_A} where _A, ::AbstractArray) (3 children)
              2: superseding all(f, itr) in Base at reduce.jl:918 with MethodInstance for all(::Base.var"#388#389"{_A} where _A, ::Any) (3 children)

 inserting any(f::Function, x::FillArrays.AbstractFill) in FillArrays at /home/tim/.julia/packages/FillArrays/NjFh2/src/FillArrays.jl:555 invalidated:
   backedges: 1: superseding any(f::Function, a::AbstractArray; dims) in Base at reducedim.jl:877 with MethodInstance for any(::typeof(ismissing), ::AbstractArray) (1 children)
              2: superseding any(f, itr) in Base at reduce.jl:871 with MethodInstance for any(::typeof(ismissing), ::Any) (1 children)
              3: superseding any(f, itr) in Base at reduce.jl:871 with MethodInstance for any(::LoweredCodeUtils.var"#11#12"{_A} where _A, ::Any) (2 children)
              4: superseding any(f::Function, a::AbstractArray; dims) in Base at reducedim.jl:877 with MethodInstance for any(::LoweredCodeUtils.var"#11#12"{_A} where _A, ::AbstractArray) (4 children)

 inserting broadcasted(::Base.Broadcast.DefaultArrayStyle{N}, op, r::FillArrays.AbstractFill{T,N,Axes} where Axes) where {T, N} in FillArrays at /home/tim/.julia/packages/FillArrays/NjFh2/src/fillbroadcast.jl:8 invalidated:
   backedges: 1: superseding broadcasted(::S, f, args...) where S<:Base.Broadcast.BroadcastStyle in Base.Broadcast at broadcast.jl:1265 with MethodInstance for broadcasted(::Base.Broadcast.BroadcastStyle, ::typeof(JuliaInterpreter._Typeof), ::Any) (1 children)
              2: superseding broadcasted(::S, f, args...) where S<:Base.Broadcast.BroadcastStyle in Base.Broadcast at broadcast.jl:1265 with MethodInstance for broadcasted(::Base.Broadcast.BroadcastStyle, ::typeof(string), ::AbstractArray) (177 children)
```

Your specific results may differ from this, depending on which version of Julia and of packages you are using.
In this case, you can see that three methods (one for `all`, one for `any`, and one for `broadcasted`) triggered invalidations.
Perusing this list, you can see that methods in `Base`, `LoweredCodeUtils`, and `JuliaInterpreter` (the latter two were loaded by `Revise`) got invalidated by methods defined in FillArrays.

The most consequential ones (the ones with the most children) are listed last, and should be where you direct your attention first.
That last entry looks particularly problematic, so let's extract it:

```julia
julia> methinvs = trees[end];

julia> root = methinvs.backedges[end]
MethodInstance for broadcasted(::Base.Broadcast.BroadcastStyle, ::typeof(string), ::AbstractArray) at depth 0 with 177 children

julia> show(root; maxdepth=10)
MethodInstance for broadcasted(::Base.Broadcast.BroadcastStyle, ::typeof(string), ::AbstractArray) (177 children)
 MethodInstance for broadcasted(::typeof(string), ::AbstractArray) (176 children)
  MethodInstance for #unpack#104(::Bool, ::typeof(Pkg.PlatformEngines.unpack), ::String, ::String) (175 children)
   MethodInstance for (::Pkg.PlatformEngines.var"#unpack##kw")(::NamedTuple{(:verbose,),Tuple{Bool}}, ::typeof(Pkg.PlatformEngines.unpack), ::String, ::String) (174 children)
    MethodInstance for #download_verify_unpack#109(::Nothing, ::Bool, ::Bool, ::Bool, ::Bool, ::typeof(Pkg.PlatformEngines.download_verify_unpack), ::String, ::Nothing, ::String) (165 children)
     MethodInstance for (::Pkg.PlatformEngines.var"#download_verify_unpack##kw")(::NamedTuple{(:ignore_existence, :verbose),Tuple{Bool,Bool}}, ::typeof(Pkg.PlatformEngines.download_verify_unpack), ::String, ::Nothing, ::String) (33 children)
      MethodInstance for (::Pkg.Artifacts.var"#39#40"{Bool,String,Nothing})(::String) (32 children)
       MethodInstance for create_artifact(::Pkg.Artifacts.var"#39#40"{Bool,String,Nothing}) (31 children)
        MethodInstance for #download_artifact#38(::Bool, ::Bool, ::typeof(Pkg.Artifacts.download_artifact), ::Base.SHA1, ::String, ::Nothing) (30 children)
         MethodInstance for (::Pkg.Artifacts.var"#download_artifact##kw")(::NamedTuple{(:verbose, :quiet_download),Tuple{Bool,Bool}}, ::typeof(Pkg.Artifacts.download_artifact), ::Base.SHA1, ::String, ::Nothing) (23 children)
          MethodInstance for (::Pkg.Artifacts.var"#download_artifact##kw")(::NamedTuple{(:verbose, :quiet_download),Tuple{Bool,Bool}}, ::typeof(Pkg.Artifacts.download_artifact), ::Base.SHA1, ::String) (22 children)
          ⋮
        ⋮
     MethodInstance for (::Pkg.PlatformEngines.var"#download_verify_unpack##kw")(::NamedTuple{(:ignore_existence,),Tuple{Bool}}, ::typeof(Pkg.PlatformEngines.download_verify_unpack), ::String, ::Nothing, ::String) (130 children)
      MethodInstance for (::Pkg.Types.var"#94#97"{Pkg.Types.Context,String,Pkg.Types.RegistrySpec})(::String) (116 children)
       MethodInstance for #mktempdir#21(::String, ::typeof(mktempdir), ::Pkg.Types.var"#94#97"{Pkg.Types.Context,String,Pkg.Types.RegistrySpec}, ::String) (115 children)
        MethodInstance for mktempdir(::Pkg.Types.var"#94#97"{Pkg.Types.Context,String,Pkg.Types.RegistrySpec}, ::String) (114 children)
         MethodInstance for mktempdir(::Pkg.Types.var"#94#97"{Pkg.Types.Context,String,Pkg.Types.RegistrySpec}) (113 children)
          MethodInstance for clone_or_cp_registries(::Pkg.Types.Context, ::Vector{Pkg.Types.RegistrySpec}, ::String) (112 children)
          ⋮
     ⋮
   ⋮
```

Here you can see a much more complex branching structure.
From this, you can see that methods in `Pkg` are the most significantly affected;
you could expect that loading `FillArrays` might slow down your next `Pkg` operation (perhaps depending on which operation you choose) executed in this same session.

Again, if you're following along, it's possible that you'll see something quite different, if subsequent development has protected `Pkg` against this form of invalidation.

## Filtering invalidations

Some method definitions trigger widespread invalidation.
If you don't have time to fix all of them, you might want to focus on a specific set of invalidations.
For instance, you might be the author of `PkgA` and you've noted that loading `PkgB` invalidates a lot of `PkgA`'s code.
In that case, you might want to find just those invalidations triggered in your package.
You can find them with [`filtermod`](@ref):

```julia
trees = invalidation_trees(@snoopr using PkgB)
ftrees = filtermod(PkgA, trees)
```

`filtermod` only selects trees where the root method was defined in the specified module.

A more selective yet exhaustive tool is [`findcaller`](@ref), which allows you to find the path through the trees to a particular method:

```julia
m = @which f(data)                  # look for the "path" that invalidates this method
f(data)                             # run once to force compilation
using SnoopCompile
trees = invalidation_trees(@snoopr using SomePkg)
invs = findcaller(m, trees)         # select the branch that invalidated a compiled instance of `m`
```

When you don't know which method to choose, but know an operation that got slowed down by loading `SomePkg`, you can use `@snoopi` to find methods that needed to be recompiled. See [`findcaller`](@ref) for further details.


## Fixing invalidations

In addition to the text below, there is a
[video](https://www.youtube.com/watch?v=7VbXbI6OmYo) illustrating many
of the same package features. The video also walks through a real-world
example fixing invalidations that stemmed from inference problems in
some of `Pkg`'s code.

### ascend

SnoopCompile, partnering with the remarkable [Cthulhu](https://github.com/JuliaDebug/Cthulhu.jl),
provides a tool called `ascend` to simplify diagnosing and fixing invalidations.
To demonstrate this tool, let's use it on our test methods defined above.
For best results, you'll want to copy those method definitions into a file:

```julia
f(::Real) = 1
callf(container) = f(container[1])
call2f(container) = callf(container)

c64  = [1.0]; c32 = [1.0f0]; cabs = AbstractFloat[1.0];
call2f(c64)
call2f(c32)
call2f(cabs)

using SnoopCompileCore
invalidations = @snoopr f(::Float64) = 2
using SnoopCompile
trees = invalidation_trees(invalidations)
method_invalidations = trees[1]
```

and `include` it into a fresh session.  (The full functionality of `ascend` doesn't work for methods defined at the REPL, but does if the methods are defined in a file.)
In this demo, I called that file `/tmp/snoopr.jl`.


We start with

```julia
julia> root = method_invalidations.backedges[end]
MethodInstance for f(::AbstractFloat) at depth 0 with 2 children
```

(It's common to start from the last element of `backedges` or `mt_backedges` since these have the largest number of children and are therefore most consequential.)
Then:

```julia
julia> ascend(root)
Choose a call for analysis (q to quit):
 >   f(::AbstractFloat)
       callf(::Vector{AbstractFloat})
         call2f(::Vector{AbstractFloat})
```

This is an interactive menu: press the down arrow to go down, the up arrow to go up, and `Enter` to select an item for more detailed analysis.
In large trees, you may also want to "fold" nodes of the tree (collapsing it so that the children are no longer displayed), particularly if you are working your way through a long series of invalidations and want to hide ones you've already dealt with. You toggle folding using the space bar, and folded nodes are printed with a `+` in front of them.

For example, if we press the down arrow once, we get

```julia
julia> ascend(root)
Choose a call for analysis (q to quit):
     f(::AbstractFloat)
 >     callf(::Vector{AbstractFloat})
         call2f(::Vector{AbstractFloat})
```

Now hit `Enter` to select it:

```julia
Choose caller of MethodInstance for f(::AbstractFloat) or proceed to typed code:
 > "/tmp/snoopr.jl", callf: lines [2]
   Browse typed code
```

This is showing you another menu, with only two options (a third is to go back by hitting `q`).
The first entry shows you the option to open the "offending" source file in `callf` at the position of the call to the parent node of `callf`, which in this case is `f`.
(Sometimes there will be more than one call to the parent within the method, in which case instead of showing `[1]` it might show `[1, 17, 39]` indicating each separate location.)
Selecting this option, when available, is typically the best way to start because you can sometimes resolve the problem just by inspection of the source.

If you hit the down arrow

```julia
Choose caller of MethodInstance for f(::AbstractFloat) or proceed to typed code:
   "/tmp/snoopr.jl", callf: lines [2]
 > Browse typed code
```

and then hit `Enter`, this is what you see:

```julia
│ ─ %-1  = invoke callf(::Vector{AbstractFloat})::Int64
Variables
  #self#::Core.Const(callf, false)
  container::Vector{AbstractFloat}

Body::Int64
    @ /tmp/snoopr.jl:2 within `callf'
1 ─ %1 = Base.getindex(container, 1)::AbstractFloat
│   %2 = Main.f(%1)::Int64
└──      return %2

Select a call to descend into or ↩ to ascend. [q]uit. [b]ookmark.
Toggles: [o]ptimize, [w]arn, [d]ebuginfo, [s]yntax highlight for Source/LLVM/Native.
Show: [S]ource code, [A]ST, [L]LVM IR, [N]ative code
Advanced: dump [P]arams cache.

 • %1  = invoke getindex(::Vector{AbstractFloat},::Int64)::AbstractFloat
   %2  = call #f(::AbstractFloat)::Int64
   ↩
```

This is output from Cthulhu, and you should see its documentation for more information.
(See also [this video](https://www.youtube.com/watch?v=qf9oA09wxXY).)
While it takes a bit of time to master Cthulhu, it is an exceptionally powerful tool for diagnosing and fixing inference issues.

### "Dead ends": finding runtime callers with MethodAnalysis

When a call is made by runtime dispatch and the world of available methods to handle the call does not narrow the types
beyond what is known to the caller, the call-chain terminates.
Here is a real-world example (one that may already be "fixed" by the time you read this) from analyzing invalidations triggered by specializing `Base.unsafe_convert(::Type{Ptr{T}}, ::Base.RefValue{S})` for specific types `S` and `T`:

```
julia> ascend(root)
Choose a call for analysis (q to quit):
 >   unsafe_convert(::Type{Ptr{Nothing}}, ::Base.RefValue{_A} where _A)
       _show_default(::IOBuffer, ::Any)
         show_default(::IOBuffer, ::Function)
           show_function(::IOBuffer, ::Function, ::Bool)
             print(::IOBuffer, ::Function)
         show_default(::IOBuffer, ::ProcessFailedException)
           show(::IOBuffer, ::ProcessFailedException)
             print(::IOBuffer, ::ProcessFailedException)
         show_default(::IOBuffer, ::Sockets.IPAddr)
           show(::IOBuffer, ::Sockets.IPAddr)
```

Unfortunately for our investigations, none of these "top level" callers have defined backedges. (Overall, it's very fortunate that they don't, in that runtime dispatch without backedges avoids any need to invalidate the caller; the alternative would be extremely long chains of completely unnecessary invalidation, which would have many undesirable consequences.)

If you want to fix such "short chains" of invalidation, one strategy is to identify callers by brute force search enabled by the `MethodAnalysis` package.
For example, one can discover the caller of `show(::IOBuffer, ::Sockets.IPAddr)` with

```julia
using MethodAnalysis       # best from a fresh Julia session
mis = methodinstances();   # collect all *existing* MethodInstances (any future compilation will be ignored)
# Create a predicate that finds these argument types
using Sockets
argmatch(typs) = length(typs) >= 2 && typs[1] === IOBuffer && typs[2] === Sockets.IPAddr
# Find any callers
callers = findcallers(show, argmatch, mis)
```

which yields a single hit in `print(::IOBuffer, ::IPAddr)`.
This too lacks any backedges, so a second application `findcallers(print, argmatch, mis)` links to `print_to_string(::IPAddr)`.
This MethodInstance has a backedge to `string(::IPAddr)`, which has backedges to the method `Distributed.connect_to_worker(host::AbstractString, port::Integer)`.
A bit of digging shows that this calls `Sockets.getaddrinfo` to look up an IP address, and this is inferred to return an `IPAddr` but the concrete type is unknown.
A potential fix for this situation is described below.

This does not always work; for example, trying something similar for `ProcessExitedException` fails, likely because the call was made with even less type information.
We might be able to find it with a more general predicate, for example

```
argmatch(typs) = length(typs) >= 2 && typs[1] === IOBuffer && ProcessExitedException <: typs[2]
```

but this returns a lot of candidates and it is difficult to guess which of these might be the culprit(s).
Finally, `findcallers` only detects method calls that are "hard-wired" into type-inferred code; if the call we're seeking was made from toplevel, or if the function itself was a runtime variable, there is no hope that `findcallers` will detect it.

### Tips for fixing invalidations

Invalidations occur in situations like our `call2f(c64)` example, where we changed our mind about what value `f` should return for `Float64`.
Julia could not have returned the newly-correct answer without recompiling the call chain.

Aside from cases like these, most invalidations occur whenever new types are introduced,
and some methods were previously compiled for abstract types.
In some cases, this is inevitable, and the resulting invalidations simply need to be accepted as a consequence of a dynamic, updateable language.
(As recommended above, you can often minimize invalidations by loading all your code at the beginning of your session, before triggering the compilation of more methods.)
However, in many circumstances an invalidation indicates an opportunity to improve code.
In our first example, note that the call `call2f(c32)` did not get invalidated: this is because the compiler
knew all the specific types, and new methods did not affect any of those types.
The main tips for writing invalidation-resistant code are:

- use [concrete types](https://docs.julialang.org/en/latest/manual/performance-tips/#man-performance-abstract-container-1) wherever possible
- write inferrable code (be especially aware of [julia issue 15276](https://github.com/JuliaLang/julia/issues/15276))
- don't engage in [type-piracy](https://docs.julialang.org/en/latest/manual/style-guide/#Avoid-type-piracy-1) (our `c64` example is essentially like type-piracy, where we redefined behavior for a pre-existing type)

Since these tips also improve performance and allow programs to behave more predictably,
these guidelines are not intrusive.
Indeed, searching for and eliminating invalidations can help you improve the quality of your code.

#### Adding type annotations

In cases where invalidations occur, but you can't use concrete types (there are indeed many valid uses of `Vector{Any}`),
you can often prevent the invalidation using some additional knowledge.
One common example is extracting information from an [IOContext](https://docs.julialang.org/en/latest/manual/networking-and-streams/#IO-Output-Contextual-Properties-1) structure, which is roughly defined as

```julia
struct IOContext{IO_t <: IO} <: AbstractPipe
    io::IO_t
    dict::ImmutableDict{Symbol, Any}
end
```

There are good reasons to use a value-type of `Any`, but that makes it impossible for the compiler to infer the type of any object looked up in an IOContext.
Fortunately, you can help!
For example, the documentation specifies that the `:color` setting should be a `Bool`, and since it appears in documentation it's something we can safely enforce.
Changing

```
iscolor = get(io, :color, false)
```

to

```
iscolor = get(io, :color, false)::Bool     # assert that the rhs is Bool-valued
```

will throw an error if it isn't a `Bool`, and this allows the compiler to take advantage of the type being known in subsequent operations.

We've already seen another relevant example above, where `getaddrinfo(::AbstractString)` was inferred to return an `IPAddr`, which is an abstract type.
Since there are only two such types supported by the Sockets library,
one potential fix is to annotate the returned value from `getaddrinfo` to be `Union{IPv4,IPv6}`.
This will allow Julia to [union-split](https://julialang.org/blog/2018/08/union-splitting/) future operations made using the returned value.

Before turning to a more complex example, it's worth noting that this trick applied to field accesses of abstract types is often one of the simplest ways to fix widespread inference problems.
This is such an important case that it is described in the section below.

As a more detailed example, suppose you're writing code that parses Julia's `Expr` type:

```julia
julia> ex = :(Array{Float32,3})
:(Array{Float32, 3})

julia> dump(ex)
Expr
  head: Symbol curly
  args: Vector{Any(3,))
    1: Symbol Array
    2: Symbol Float32
    3: Int64 3
```

`ex.args` is a `Vector{Any}`.
However, for a `:curly` expression only certain types will be found among the arguments; you could write key portions of your code as

```julia
a = ex.args[2]
if a isa Symbol
    # inside this block, Julia knows `a` is a Symbol, and so methods called on `a` will be resistant to invalidation
    foo(a)
elseif a isa Expr && length((a::Expr).args) > 2
    a::Expr         # sometimes you have to help inference by adding a type-assert
    x = bar(a)      # `bar` is now resistant to invalidation
elseif a isa Integer
    # even though you've not made this fully-inferrable, you've at least reduced the scope for invalidations
    # by limiting the subset of `foobar` methods that might be called
    y = foobar(a)
end
```

Other tricks include replacing broadcasting on `v::Vector{Any}` with `Base.mapany(f, v)`--`mapany` avoids trying to narrow the type of `f(v[i])` and just assumes it will be `Any`, thereby avoiding invalidations of many `convert` methods.

Adding type-assertions and fixing inference problems are the most common approaches for fixing invalidations.
You can discover these manually, but using Cthulhu is highly recommended.

#### Inferrable field access for abstract types

When invalidations happen for methods that manipulate fields of abstract types, often there is a simple solution: create an "interface" for the abstract type specifying that certain fields must have certain types.
Here's an example:

```
abstract type AbstractDisplay end

struct Monitor <: AbstractDisplay
    height::Int
    width::Int
    maker::String
end

struct Phone <: AbstractDisplay
    height::Int
    width::Int
    maker::Symbol
end

function Base.show(@nospecialize(d::AbstractDisplay), x)
    str = string(x)
    w = d.width
    if length(str) > w  # do we have to truncate to fit the display width?
        ...
```

In this `show` method, we've deliberately chosen to prevent specialization on the specific type of `AbstractDisplay` (to reduce the total number of times we have to compile this method).
As a consequence, Julia's inference generally will not realize that `d.width` returns an `Int`--it might be able to discover that by exhaustively checking all subtypes, but if there are a lot of such subtypes then such checks would slow compilation considerably.

Fortunately, you can help by defining an interface for generic `AbstractDisplay` objects:

```
function Base.getproperty(d::AbstractDisplay, name::Symbol)
    if name === :height
        return getfield(d, :height)::Int
    elseif name === :width
        return getfield(d, :width)::Int
    elseif name === :maker
        return getfield(d, :maker)::Union{String,Symbol}
    end
    return getfield(d, name)
end
```

Julia's [constant propagation](https://en.wikipedia.org/wiki/Constant_folding) will ensure that most accesses of those fields will be determined at compile-time, so this simple change robustly fixes many inference problems.

#### Handling edge cases

You can sometimes get invalidations from failing to handle "formal" possibilities.
For example, operations with regular expressions might return a `Union{Nothing, RegexMatch}`.
You can sometimes get poor type inference by writing code that fails to take account of the possibility that `nothing` might be returned.
For example, a comprehension

```julia
ms = [m.match for m in match.((rex,), my_strings)]
```
might be replaced with
```julia
ms = [m.match for m in match.((rex,), my_strings) if m !== nothing]
```
and return a better-typed result.
