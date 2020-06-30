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

To record the invalidations caused by defining new methods, use `@snoopr` from SnoopCompileCore:
```julia
using SnoopCompileCore
invalidations = @snoopr begin
 # new methods definition
end
```
and use `invalidation_trees` from SnoopCompileAnalysis to aggregate the information as a collection of [tree structures](https://en.wikipedia.org/wiki/Tree_structure):
```julia
using SnoopCompileAnalysis
trees = invalidation_trees(invalidations)
```

We can illustrate this process with the following example:

```jldoctest invalidations
julia> f(::Real) = 1;

julia> callf(container) = f(container[1]);

julia> call2f(container) = callf(container);
```

Let's run this with different container types:
```jldoctest invalidations
julia> c64  = [1.0]; c32 = [1.0f0]; cabs = AbstractFloat[1.0];

julia> call2f(c64)
1

julia> call2f(c32)
1

julia> call2f(cabs)
1
```

It's important that you actually execute these methods: code doesn't get compiled until it gets run, and invalidations only affect compiled code.

Now we'll define a new `f` method, one specialized for `Float64`.
So we can see the consequences for the compiled code, we'll make this definition while snooping on the compiler with `@snoopr`:

```jldoctest invalidations
julia> trees = invalidation_trees(@snoopr f(::Float64) = 2)
1-element Array{SnoopCompileAnalysis.MethodInvalidations,1}:
 inserting f(::Float64) in Main at REPL[9]:1 invalidated:
   backedges: 1: superseding f(::Real) in Main at REPL[2]:1 with MethodInstance for f(::Float64) (2 children) more specific
              2: superseding f(::Real) in Main at REPL[2]:1 with MethodInstance for f(::AbstractFloat) (2 children) more specific
   2 mt_cache
```

The list of `MethodInvalidations` indicates that some previously-compiled code got invalidated.
In this case, "`inserting f(::Float64)`" means that a new method, for `f(::Float64)`, was added.
There were two proximal triggers for the invalidation, both of which superseded the method `f(::Real)`.
One of these had been compiled specifically for `Float64`, due to our `call2f(c64)`.
The other had been compiled specifically for `AbstractFloat`, due to our `call2f(cabs)`.

You can look at these invalidation trees in greater detail:

```jldoctest invalidations
julia> method_invalidations = trees[1];    # invalidations stemming from a single method

julia> root = method_invalidations.backedges[1]
MethodInstance for f(::Float64) at depth 0 with 2 children

julia> show(root)
MethodInstance for f(::Float64) (2 children)
 MethodInstance for callf(::Array{Float64,1}) (1 children)
 ⋮

julia> show(root; minchildren=0)
MethodInstance for f(::Float64) (2 children)
 MethodInstance for callf(::Array{Float64,1}) (1 children)
  MethodInstance for call2f(::Array{Float64,1}) (0 children)
```

You can see that the sequence of invalidations proceeded all the way up to `call2f`.
Examining `root2 = method_invalidations.backedges[2]` yields similar results, but for `Array{AbstractFloat,1}`.

The structure of these trees can be considerably more complicated. For example, if `callf`
also got called by some other method, and that method had also been executed (forcing it to be compiled),
then `callf` would have multiple children.
This is often seen with more complex, real-world tests:

```julia
julia> trees = invalidation_trees(@snoopr using SIMD)
4-element Array{SnoopCompileAnalysis.MethodInvalidations,1}:
 inserting convert(::Type{Tuple{Vararg{R,N}}}, v::Vec{N,T}) where {N, R, T} in SIMD at /home/tim/.julia/packages/SIMD/Am38N/src/SIMD.jl:182 invalidated:
   mt_backedges: 1: signature Tuple{typeof(convert),Type{Tuple{DataType,DataType,DataType}},Any} triggered MethodInstance for Pair{DataType,Tuple{DataType,DataType,DataType}}(::Any, ::Any) (0 children) ambiguous
                 2: signature Tuple{typeof(convert),Type{NTuple{8,DataType}},Any} triggered MethodInstance for Pair{DataType,NTuple{8,DataType}}(::Any, ::Any) (0 children) ambiguous
                 3: signature Tuple{typeof(convert),Type{NTuple{7,DataType}},Any} triggered MethodInstance for Pair{DataType,NTuple{7,DataType}}(::Any, ::Any) (0 children) ambiguous

 inserting convert(::Type{Tuple}, v::Vec{N,T}) where {N, T} in SIMD at /home/tim/.julia/packages/SIMD/Am38N/src/SIMD.jl:188 invalidated:
   mt_backedges: 1: signature Tuple{typeof(convert),Type{Tuple},Any} triggered MethodInstance for Distributed.RemoteDoMsg(::Any, ::Any, ::Any) (1 children) more specific
                 2: signature Tuple{typeof(convert),Type{Tuple},Any} triggered MethodInstance for Distributed.CallMsg{:call}(::Any, ::Any, ::Any) (1 children) more specific
                 3: signature Tuple{typeof(convert),Type{Tuple},Any} triggered MethodInstance for Distributed.CallMsg{:call_fetch}(::Any, ::Any, ::Any) (1 children) more specific
                 4: signature Tuple{typeof(convert),Type{Tuple},Any} triggered MethodInstance for Distributed.CallWaitMsg(::Any, ::Any, ::Any) (4 children) more specific
   12 mt_cache

 inserting <<(x1::T, v2::Vec{N,T}) where {N, T<:Union{Bool, Int128, Int16, Int32, Int64, Int8, UInt128, UInt16, UInt32, UInt64, UInt8}} in SIMD at /home/tim/.julia/packages/SIMD/Am38N/src/SIMD.jl:1061 invalidated:
   mt_backedges: 1: signature Tuple{typeof(<<),UInt64,Any} triggered MethodInstance for <<(::UInt64, ::Integer) (0 children) ambiguous
                 2: signature Tuple{typeof(<<),UInt64,Any} triggered MethodInstance for copy_chunks_rtol!(::Array{UInt64,1}, ::Integer, ::Integer, ::Integer) (0 children) ambiguous
                 3: signature Tuple{typeof(<<),UInt64,Any} triggered MethodInstance for copy_chunks_rtol!(::Array{UInt64,1}, ::Int64, ::Int64, ::Integer) (0 children) ambiguous
                 4: signature Tuple{typeof(<<),UInt64,Any} triggered MethodInstance for copy_chunks_rtol!(::Array{UInt64,1}, ::Integer, ::Int64, ::Integer) (0 children) ambiguous
                 5: signature Tuple{typeof(<<),UInt64,Any} triggered MethodInstance for <<(::UInt64, ::Unsigned) (16 children) ambiguous
   20 mt_cache

 inserting +(s1::Union{Bool, Float16, Float32, Float64, Int128, Int16, Int32, Int64, Int8, UInt128, UInt16, UInt32, UInt64, UInt8, Ptr}, v2::Vec{N,T}) where {N, T<:Union{Float16, Float32, Float64}} in SIMD at /home/tim/.julia/packages/SIMD/Am38N/src/SIMD.jl:1165 invalidated:
   mt_backedges:  1: signature Tuple{typeof(+),Ptr{UInt8},Any} triggered MethodInstance for handle_err(::JuliaInterpreter.Compiled, ::JuliaInterpreter.Frame, ::Any) (0 children) ambiguous
                  2: signature Tuple{typeof(+),Ptr{UInt8},Any} triggered MethodInstance for #methoddef!#5(::Bool, ::typeof(LoweredCodeUtils.methoddef!), ::Any, ::Set{Any}, ::JuliaInterpreter.Frame) (0 children) ambiguous
                  3: signature Tuple{typeof(+),Ptr{UInt8},Any} triggered MethodInstance for #get_def#94(::Set{Tuple{Revise.PkgData,String}}, ::typeof(Revise.get_def), ::Method) (0 children) ambiguous
                  4: signature Tuple{typeof(+),Ptr{Nothing},Any} triggered MethodInstance for filter_valid_cachefiles(::String, ::Array{String,1}) (0 children) ambiguous
                  5: signature Tuple{typeof(+),Ptr{Union{Int64, Symbol}},Any} triggered MethodInstance for pointer(::Array{Union{Int64, Symbol},N} where N, ::Int64) (1 children) ambiguous
                  6: signature Tuple{typeof(+),Ptr{Char},Any} triggered MethodInstance for pointer(::Array{Char,N} where N, ::Int64) (2 children) ambiguous
                  7: signature Tuple{typeof(+),Ptr{_A} where _A,Any} triggered MethodInstance for pointer(::Array{T,N} where N where T, ::Int64) (4 children) ambiguous
                  8: signature Tuple{typeof(+),Ptr{Nothing},Any} triggered MethodInstance for _show_default(::IOContext{Base.GenericIOBuffer{Array{UInt8,1}}}, ::Any) (49 children) ambiguous
                  9: signature Tuple{typeof(+),Ptr{Nothing},Any} triggered MethodInstance for _show_default(::Base.GenericIOBuffer{Array{UInt8,1}}, ::Any) (336 children) ambiguous
                 10: signature Tuple{typeof(+),Ptr{UInt8},Any} triggered MethodInstance for pointer(::String, ::Integer) (1027 children) ambiguous
   2 mt_cache

```

Your specific output will surely be different from this, depending on which packages you have loaded,
which versions of those packages are installed, and which version of Julia you are using.
In this example, there were four different methods that triggered invalidations, and the invalidated methods were in `Base`,
`Distributed`, `JuliaInterpeter`, and `LoweredCodeUtils`. (The latter two were a consequence of loading `Revise`.)
You can see that collectively more than a thousand independent compiled methods needed to be invalidated; indeed, the last
entry alone invalidates 1027 method instances:

```julia
julia> sig, root = trees[end].mt_backedges[10]
Pair{Any,SnoopCompile.InstanceNode}(Tuple{typeof(+),Ptr{UInt8},Any}, MethodInstance for pointer(::String, ::Integer) at depth 0 with 1027 children)

julia> root
MethodInstance for pointer(::String, ::Integer) at depth 0 with 1027 children

julia> show(root)
MethodInstance for pointer(::String, ::Integer) (1027 children)
 MethodInstance for repeat(::String, ::Integer) (1023 children)
  MethodInstance for ^(::String, ::Integer) (1019 children)
   MethodInstance for #handle_message#2(::Nothing, ::Base.Iterators.Pairs{Union{},Union{},Tuple{},NamedTuple{(),Tuple{}}}, ::typeof(Base.CoreLogging.handle_message), ::Logging.ConsoleLogger, ::Base.CoreLogging.LogLevel, ::String, ::Module, ::Symbol, ::Symbol, ::String, ::Int64) (906 children)
    MethodInstance for handle_message(::Logging.ConsoleLogger, ::Base.CoreLogging.LogLevel, ::String, ::Module, ::Symbol, ::Symbol, ::String, ::Int64) (902 children)
     MethodInstance for log_event_global!(::Pkg.Resolve.Graph, ::String) (35 children)
     ⋮
     MethodInstance for #artifact_meta#20(::Pkg.BinaryPlatforms.Platform, ::typeof(Pkg.Artifacts.artifact_meta), ::String, ::Dict{String,Any}, ::String) (43 children)
     ⋮
     MethodInstance for Dict{Base.UUID,Pkg.Types.PackageEntry}(::Dict) (79 children)
     ⋮
     MethodInstance for read!(::Base.Process, ::LibGit2.GitCredential) (80 children)
     ⋮
     MethodInstance for handle_err(::JuliaInterpreter.Compiled, ::JuliaInterpreter.Frame, ::Any) (454 children)
     ⋮
    ⋮
   ⋮
  ⋮
 ⋮
⋮
```

Many nodes in this tree have multiple "child" branches.

!!! note
    These `trees` are sorted so that the last items have the largest number of children.
    It works this way so that long printouts don't have the most important information scroll off the
    top of the screen.

## Filtering invalidations

Some methods trigger widespread invalidation.
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
f(data)                             # run once to force compilation
m = @which f(data)
using SnoopCompile
trees = invalidation_trees(@snoopr using SomePkg)
invs = findcaller(m, trees)
```

When you don't know which method to choose, but know an operation that got slowed down by loading `SomePkg`, you can use `@snoopi` to find methods that needed to be recompiled. See [`findcaller`](@ref) for further details.


## Avoiding or fixing invalidations

### Tools for fixing invalidations: ascend

SnoopCompile, partnering with the remarkable [Cthulhu.jl](https://github.com/JuliaDebug/Cthulhu.jl),
provides a tool called `ascend` to simplify diagnosing and fixing invalidations.
To demonstrate this tool, let's use it on our `call2f` `method_invalidations` tree from above.
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
       callf(::Array{AbstractFloat,1})
         call2f(::Array{AbstractFloat,1})
```

This is an interactive menu: press the down arrow to go down, the up arrow to go up, and `Enter` to select an item for more detailed analysis.
In large trees, you may also want to "fold" nodes of the tree (collapsing it so that the children are no longer displayed), particularly if you are working your way through a long series of invalidations and want to hide ones you've already dealt with. You toggle folding using the space bar, and folded nodes are printed with a `+` in front of them.

For example, if we press the down arrow once, we get

```julia
julia> ascend(root)
Choose a call for analysis (q to quit):
     f(::AbstractFloat)
 >     callf(::Array{AbstractFloat,1})
         call2f(::Array{AbstractFloat,1})
```

Now hit `Enter` to select it:

```julia
Choose caller of MethodInstance for f(::AbstractFloat) or proceed to typed code:
 > "REPL[3]", callf: lines [1]
   Browse typed code
```

This is showing you another menu, with only two option (a third is to go back by hitting `q`).
The first entry shows you the option to open the "offending" source file in `callf` at the position of the call to the parent node of `callf`, which in this case is `f`.
(Sometimes there will be more than one call to the parent within the method, in which case instead of showing `[1]` it might show `[1, 17, 39]` indicating each separate location.)
While in this case this isn't useful (methods defined in the REPL are not supported), selecting this option, when available, is typically the best way to start because you can sometimes resolve the problem from this information alone.

If you hit the down arrow

```julia
Choose caller of MethodInstance for f(::AbstractFloat) or proceed to typed code:
   "REPL[3]", callf: lines [1]
 > Browse typed code
```

and then hit `Enter`, this is what you see:

```julia
│ ─ %-1  = invoke callf(::Array{AbstractFloat,1})::Int64
Variables
  #self#::Core.Compiler.Const(callf, false)
  container::Array{AbstractFloat,1}

Body::Int64
    @ REPL[3]:1 within callf
1 ─ %1 = Base.getindex(container, 1)::AbstractFloat
│   %2 = Main.f(%1)::Int64
└──      return %2

Select a call to descend into or ↩ to ascend. [q]uit. [b]ookmark.
Toggles: [o]ptimize, [w]arn, [d]ebuginfo, [s]yntax highlight for Source/LLVM/Native.
Show: [S]ource code, [A]ST, [L]LVM IR, [N]ative code
Advanced: dump [P]arams cache.

 • %1  = invoke getindex(::Array{AbstractFloat,1},::Int64)::AbstractFloat
   %2  = call #f(::AbstractFloat)::Int64
   ↩
```

This is output from Cthulhu, and you should see its documentation for more information.
(See also [this video](https://www.youtube.com/watch?v=qf9oA09wxXY).)
While it takes a bit of time to master Cthulhu, it is an exceptionally powerful tool for diagnosing and fixing inference issues.

### Tips for fixing invalidations

Invalidations occur in situations like our `call2f(c64)` example, where we changed our mind about what value `f` should return for `Float64`.
Julia could not have returned the newly-correct answer without recompiling the call chain.

Aside from cases like these, most invalidations occur whenever new types are introduced,
and some methods were previously compiled for abstract types.
In some cases, this is inevitable, and the resulting invalidations simply need to be accepted as a consequence of a dynamic, updateable language.
(You can often minimize invalidations by loading all your code at the beginning of your session, before triggering the compilation of more methods.)
However, in many circumstances an invalidation indicates an opportunity to improve code.
In our first example, note that the call `call2f(c32)` did not get invalidated: this is because the compiler
knew all the specific types, and new methods did not affect any of those types.
The main tips for writing invalidation-resistant code are:

- use [concrete types](https://docs.julialang.org/en/latest/manual/performance-tips/#man-performance-abstract-container-1) wherever possible
- write inferrable code
- don't engage in [type-piracy](https://docs.julialang.org/en/latest/manual/style-guide/#Avoid-type-piracy-1) (our `c64` example is essentially like type-piracy, where we redefined behavior for a pre-existing type)

Since these tips also improve performance and allow programs to behave more predictably,
these guidelines are not intrusive.
Indeed, searching for and eliminating invalidations can help you improve the quality of your code.
In cases where invalidations occur, but you can't use concrete types (there are many valid uses of `Vector{Any}`),
you can often prevent the invalidation using some additional knowledge.
For example, suppose you're writing code that parses Julia's `Expr` type:

```julia
julia> ex = :(Array{Float32,3})
:(Array{Float32, 3})

julia> dump(ex)
Expr
  head: Symbol curly
  args: Array{Any}((3,))
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
    a = a::Expr     # sometimes you have to help inference by adding a type-assert
    x = bar(a)      # `bar` is now resistant to invalidation
elsef a isa Integer
    # even though you've not made this fully-inferrable, you've at least reduced the scope for invalidations
    # by limiting the subset of `foobar` methods that might be called
    y = foobar(a)
end
```

Adding type-assertions and fixing inference problems are the most common approaches for fixing invalidations.
You can discover these manually, but using Cthulhu is highly recommended.
