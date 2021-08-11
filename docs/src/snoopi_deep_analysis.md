# Using `@snoopi_deep` results to improve inferrability

As indicated in the [workflow](@ref), the recommended steps to reduce latency are:

- check for invalidations
- adjust method specialization in your package or its dependencies
- fix problems in type inference
- add `precompile` directives

The importance of fixing "problems" in type-inference was indicated in the [tutorial](@ref): successful precompilation requires a chain of ownership, but runtime dispatch (when inference cannot predict the callee) results in breaks in this chain.  By improving inferrability, you can convert short, unconnected call-trees into a smaller number of large call-trees that all link back to your package(s).

In practice, it also turns out that opportunities to adjust specialization are often revealed by analyzing inference failures, so this page is complementary to the previous one.

Throughout this page, we'll use the `OptimizeMe` demo, which ships with `SnoopCompile`.

!!! note
    To understand what follows, it's essential to refer to [`OptimizeMe` source code](https://github.com/timholy/SnoopCompile.jl/blob/master/examples/OptimizeMe.jl) as you follow along.

```julia
julia> using SnoopCompile

julia> cd(joinpath(pkgdir(SnoopCompile), "examples"))

julia> include("OptimizeMe.jl")
Main.OptimizeMe

julia> tinf = @snoopi_deep OptimizeMe.main()
lotsa containers:
7-element Vector{Main.OptimizeMe.Container}:
 Main.OptimizeMe.Container{Int64}(1)
 Main.OptimizeMe.Container{UInt8}(0x01)
 Main.OptimizeMe.Container{UInt16}(0xffff)
 Main.OptimizeMe.Container{Float32}(2.0f0)
 Main.OptimizeMe.Container{Char}('a')
 Main.OptimizeMe.Container{Vector{Int64}}([0])
 Main.OptimizeMe.Container{Tuple{String, Int64}}(("key", 42))
3.14 is great
2.718 is jealous
6-element Vector{Main.OptimizeMe.Object}:
 Main.OptimizeMe.Object(1)
 Main.OptimizeMe.Object(2)
 Main.OptimizeMe.Object(3)
 Main.OptimizeMe.Object(4)
 Main.OptimizeMe.Object(5)
 Main.OptimizeMe.Object(7)
InferenceTimingNode: 1.423913/2.713560 on InferenceFrameInfo for Core.Compiler.Timings.ROOT() with 77 direct children

julia> fg = flamegraph(tinf)
Node(FlameGraphs.NodeData(ROOT() at typeinfer.jl:75, 0x00, 0:2713559552))
```

If you visualize `fg` with ProfileView, you'll see something like this:

![flamegraph-OptimizeMe](assets/flamegraph-OptimizeMe.png)

From the standpoint of precompilation, this has some obvious problems:

- even though we called a single method, `OptimizeMe.main()`, there are many distinct flames separated by blank spaces. This indicates that many calls are being made by runtime dispatch:  each separate flame is a fresh entrance into inference.
- several of the flames are marked in red, indicating that they are not precompilable. While SnoopCompile does have the capability to automatically emit `precompile` directives for the non-red bars that sit on top of the red ones, in some cases the red extends to the highest part of the flame. In such cases there is no available precompile directive, and therefore no way to avoid the cost of type-inference.

Our goal will be to improve the design of `OptimizeMe` to make it more precompilable.

## Analyzing inference triggers

We'll first extract the "triggers" of inference, which is just a repackaging of part of the information contained within `tinf`.
Specifically an [`InferenceTrigger`](@ref) captures callee/caller relationships that straddle a fresh entrance to type-inference, allowing you to identify which calls were made by runtime dispatch and what `MethodInstance` they called.

```julia
julia> itrigs = inference_triggers(tinf)
76-element Vector{InferenceTrigger}:
 Inference triggered to call MethodInstance for vect(::Int64, ::Vararg{Any, N} where N) from lotsa_containers (/pathto/SnoopCompile/examples/OptimizeMe.jl:13) with specialization MethodInstance for lotsa_containers()
 Inference triggered to call MethodInstance for promote_typeof(::Int64, ::UInt8, ::Vararg{Any, N} where N) from vect (./array.jl:126) with specialization MethodInstance for vect(::Int64, ::Vararg{Any, N} where N)
 Inference triggered to call MethodInstance for promote_typeof(::UInt8, ::UInt16, ::Vararg{Any, N} where N) from promote_typeof (./promotion.jl:272) with specialization MethodInstance for promote_typeof(::Int64, ::UInt8, ::Vararg{Any, N} where N)
 ⋮
```

This indicates that a whopping 76 calls were (1) made by runtime dispatch and (2) the callee had not previously been inferred.
(There was a 77th call that had to be inferred, the original call to `main()`, but by default [`inference_triggers`](@ref) excludes calls made directly from top-level. You can change that through keyword arguments.)

!!! tip
    In the REPL, `SnoopCompile` displays `InferenceTrigger`s with yellow coloration for the callee, red for the caller method, and blue for the caller specialization. This makes it easier to quickly identify the most important information.

In some cases, this might indicate that you'll need to fix 76 separate callers; fortunately, in many cases fixing the origin of inference problems can fix a number of later callees.

### [Method triggers](@id methtrigs)

Most often, it's most convenient to organize them by the method triggering the need for inference:

```julia
julia> mtrigs = accumulate_by_source(Method, itrigs)
18-element Vector{SnoopCompile.TaggedTriggers{Method}}:
 print_matrix_row(io::IO, X::AbstractVecOrMat{T} where T, A::Vector{T} where T, i::Integer, cols::AbstractVector{T} where T, sep::AbstractString) in Base at arrayshow.jl:96 (1 callees from 1 callers)
 show(io::IO, x::T, forceuntyped::Bool, fromprint::Bool) where T<:Union{Float16, Float32, Float64} in Base.Ryu at ryu/Ryu.jl:111 (1 callees from 1 callers)
 Pair(a, b) in Base at pair.jl:15 (1 callees from 1 callers)
 vect(X...) in Base at array.jl:125 (1 callees from 1 callers)
 makeobjects() in Main.OptimizeMe at /pathto/SnoopCompile/examples/OptimizeMe.jl:36 (1 callees from 1 callers)
 show_delim_array(io::IO, itr, op, delim, cl, delim_one, i1, n) in Base at show.jl:1058 (1 callees from 1 callers)
 typeinfo_prefix(io::IO, X) in Base at arrayshow.jl:515 (2 callees from 1 callers)
 (::REPL.var"#38#39")(io) in REPL at /home/tim/src/julia-master/usr/share/julia/stdlib/v1.6/REPL/src/REPL.jl:214 (2 callees from 1 callers)
 _cat_t(dims, ::Type{T}, X...) where T in Base at abstractarray.jl:1633 (2 callees from 1 callers)
 contain_list(list) in Main.OptimizeMe at /pathto/SnoopCompile/examples/OptimizeMe.jl:27 (4 callees from 1 callers)
 promote_typeof(x, xs...) in Base at promotion.jl:272 (4 callees from 4 callers)
 combine_eltypes(f, args::Tuple) in Base.Broadcast at broadcast.jl:740 (5 callees from 1 callers)
 lotsa_containers() in Main.OptimizeMe at /pathto/SnoopCompile/examples/OptimizeMe.jl:12 (7 callees from 1 callers)
 alignment(io::IO, x) in Base at show.jl:2528 (7 callees from 7 callers)
 var"#sprint#386"(context, sizehint::Integer, ::typeof(sprint), f::Function, args...) in Base at strings/io.jl:100 (8 callees from 2 callers)
 alignment(io::IO, X::AbstractVecOrMat{T} where T, rows::AbstractVector{T} where T, cols::AbstractVector{T} where T, cols_if_complete::Integer, cols_otherwise::Integer, sep::Integer) in Base at arrayshow.jl:60 (8 callees from 2 callers)
 copyto_nonleaf!(dest, bc::Base.Broadcast.Broadcasted, iter, state, count) in Base.Broadcast at broadcast.jl:1070 (9 callees from 3 callers)
 _show_default(io::IO, x) in Base at show.jl:397 (12 callees from 1 callers)
```

The methods triggering the largest number of inference runs are shown at the bottom.
You can select methods from a particular module:

```julia
julia> modtrigs = filtermod(OptimizeMe, mtrigs)
3-element Vector{SnoopCompile.TaggedTriggers{Method}}:
 makeobjects() in Main.OptimizeMe at /home/tim/.julia/dev/SnoopCompile/examples/OptimizeMe.jl:36 (1 callees from 1 callers)
 contain_list(list) in Main.OptimizeMe at /home/tim/.julia/dev/SnoopCompile/examples/OptimizeMe.jl:27 (4 callees from 1 callers)
 lotsa_containers() in Main.OptimizeMe at /home/tim/.julia/dev/SnoopCompile/examples/OptimizeMe.jl:12 (7 callees from 1 callers)
```

Rather than filter by a single module, you can alternatively call `SnoopCompile.parcel(mtrigs)` to split them out by module.
In this case, most of the triggers came from `Base`, not `OptimizeMe`.
However, many of the failures in `Base` were nevertheless indirectly due to `OptimizeMe`: our methods in `OptimizeMe` call `Base` methods with arguments that trigger internal inference failures.
Fortunately, we'll see that using more careful design in `OptimizeMe` can avoid many of those problems.

!!! tip
    If you have a longer list of inference triggers than you feel comfortable tackling, filtering by your package's module is probably the best way to start.
    Fixing issues in the package itself can end up resolving many of the "indirect" triggers too.
    Also be sure to note the ability to filter out likely "noise" from [test suites](@ref test-suites).

If you're hoping to fix inference problems, one of the most efficient things you can do is call `summary`:

```julia
julia> mtrig = modtrigs[1]
makeobjects() in Main.OptimizeMe at /home/tim/.julia/dev/SnoopCompile/examples/OptimizeMe.jl:36 (1 callees from 1 callers)

julia> summary(mtrig)
makeobjects() in Main.OptimizeMe at /home/tim/.julia/dev/SnoopCompile/examples/OptimizeMe.jl:36 had 1 specializations
Triggering calls:
Inlined _cat at ./abstractarray.jl:1630: calling cat_t##kw (1 instances)
```

Sometimes from these hints alone you can figure out how to fix the problem.
(`Inlined _cat` means that the inference trigger did not come directly from a source line of `makeobjects` but from a call, `_cat`, that got inlined into the compiled version.
Below we'll see more concretely how to interpret this hint.)

You can also say `edit(mtrig)` and be taken directly to the method you're analyzing in your editor.
Finally, you can recover the individual triggers:

```julia
julia> mtrig.itrigs[1]
Inference triggered to call MethodInstance for (::Base.var"#cat_t##kw")(::NamedTuple{(:dims,), Tuple{Val{1}}}, ::typeof(Base.cat_t), ::Type{Int64}, ::UnitRange{Int64}, ::Vararg{Any, N} where N) from _cat (./abstractarray.jl:1630) inlined into MethodInstance for makeobjects() (/home/tim/.julia/dev/SnoopCompile/examples/OptimizeMe.jl:37)
```

This is useful if you want to analyze a method via [`ascend`](@ref ascend-itrig).
`Method`-based triggers, which may aggregate many different individual triggers, are particularly useful mostly because tools like [Cthulhu.jl](https://github.com/JuliaDebug/Cthulhu.jl) show you the inference results for the entire `MethodInstance`, allowing you to fix many different inference problems at once.

### Trigger trees

While method triggers are probably the most useful way of organizing these inference triggers, for learning purposes here we'll use a more detailed scheme, which organizes inference triggers in a tree:

```julia
julia> itree = trigger_tree(itrigs)
TriggerNode for root with 14 direct children

julia> using AbstractTrees

julia> print_tree(itree)
root
├─ MethodInstance for vect(::Int64, ::Vararg{Any, N} where N)
│  └─ MethodInstance for promote_typeof(::Int64, ::UInt8, ::Vararg{Any, N} where N)
│     └─ MethodInstance for promote_typeof(::UInt8, ::UInt16, ::Vararg{Any, N} where N)
│        └─ MethodInstance for promote_typeof(::UInt16, ::Float32, ::Vararg{Any, N} where N)
│           └─ MethodInstance for promote_typeof(::Float32, ::Char, ::Vararg{Any, N} where N)
│              ⋮
│
├─ MethodInstance for combine_eltypes(::Type, ::Tuple{Vector{Any}})
│  ├─ MethodInstance for return_type(::Any, ::Any)
│  ├─ MethodInstance for return_type(::Any, ::Any, ::UInt64)
│  ├─ MethodInstance for return_type(::Core.Compiler.NativeInterpreter, ::Any, ::Any)
│  ├─ MethodInstance for contains_is(::Core.SimpleVector, ::Any)
│  └─ MethodInstance for promote_typejoin_union(::Type{Main.OptimizeMe.Container})
├─ MethodInstance for Main.OptimizeMe.Container(::Int64)
⋮
```

The parent-child relationships are based on the backtraces at the entrance to inference,
and the nodes are organized in the order in which inference occurred.

We're going to march through these systematically. Let's start with the first of these.

### `suggest` and a fix involving manual `eltype` specification

Because the analysis of inference failures is somewhat complex, `SnoopCompile` attempts to [`suggest`](@ref) an interpretation and/or remedy for each trigger:

```
julia> suggest(itree.children[1])
/pathto/SnoopCompile/examples/OptimizeMe.jl:13: invoked callee is varargs (ignore this one, homogenize the arguments, declare an umbrella type, or force-specialize the callee MethodInstance for vect(::Int64, ::Vararg{Any, N} where N))
immediate caller(s):
1-element Vector{Base.StackTraces.StackFrame}:
 main() at OptimizeMe.jl:42
└─ ./array.jl:126: caller is varargs (ignore this one, specialize the caller vect(::Int64, ::Vararg{Any, N} where N) at array.jl:126, or improve inferrability of its caller)
   immediate caller(s):
   1-element Vector{Base.StackTraces.StackFrame}:
    lotsa_containers() at OptimizeMe.jl:13
   └─ ./promotion.jl:272: caller is varargs (ignore this one, specialize the caller promote_typeof(::Int64, ::UInt8, ::Vararg{Any, N} where N) at promotion.jl:272, or improve inferrability of its caller)
      immediate caller(s):
      1-element Vector{Base.StackTraces.StackFrame}:
       vect(::Int64, ::Vararg{Any, N} where N) at array.jl:126
      └─ ./promotion.jl:272: caller is varargs (ignore this one, specialize the caller promote_typeof(::UInt8, ::UInt16, ::Vararg{Any, N} where N) at promotion.jl:272, or improve inferrability of its caller)
         immediate caller(s):
         1-element Vector{Base.StackTraces.StackFrame}:
          promote_typeof(::Int64, ::UInt8, ::Vararg{Any, N} where N) at promotion.jl:272
         └─ ./promotion.jl:272: caller is varargs (ignore this one, specialize the caller promote_typeof(::UInt16, ::Float32, ::Vararg{Any, N} where N) at promotion.jl:272, or improve inferrability of its caller)
            immediate caller(s):
            1-element Vector{Base.StackTraces.StackFrame}:
             promote_typeof(::UInt8, ::UInt16, ::Vararg{Any, N} where N) at promotion.jl:272
            └─ ./promotion.jl:272: caller is varargs (ignore this one, specialize the caller promote_typeof(::Float32, ::Char, ::Vararg{Any, N} where N) at promotion.jl:272, or improve inferrability of its caller)
               immediate caller(s):
               1-element Vector{Base.StackTraces.StackFrame}:
                promote_typeof(::UInt16, ::Float32, ::Vararg{Any, N} where N) at promotion.jl:272
               ⋮
```

!!! tip
    In the REPL, interpretations are highlighted in color to help distinguish individual suggestions.

In this case, the interpretation for the first node is "invoked callee is varargs" and suggestions are to choose one of "ignore...homogenize...umbrella type...force-specialize".
Initially, this may seem pretty opaque.
It helps if we look at the referenced line `OptimizeMe.jl:13`:

```julia
list = [1, 0x01, 0xffff, 2.0f0, 'a', [0], ("key", 42)]
```

You'll notice above that the callee for the first node is `vect`; that's what handles the creation of the vector `[1, ...]`.
If you look back up at the `itree`, you can see that a lot of `promote_typeof` calls follow, and you can see that the types listed in the arguments match the elements in `list`.
The problem, here, is that `vect` has never been inferred for this particular combination of argument types, and the fact that the types are diverse means that Julia has decided not to specialize it for this combination.
(If Julia had specialized it, it would have been inferred when `lotsa_containers` was inferred; the fact that it is showing up as a trigger means it wasn't.)

Let's see what kind of object this line creates:

```julia
julia> typeof(list)
Vector{Any} (alias for Array{Any, 1})
```

Since it creates a `Vector{Any}`, perhaps we should just tell Julia to create such an object directly: we modify `[1, 0x01, ...]` to `Any[1, 0x01, ...]` (note the `Any` in front of `[`), so that Julia doesn't have to deduce the container type on its own.
This follows the "declare an umbrella type" suggestion.

!!! note
    "Force-specialize" means to encourage Julia to violate its heuristics and specialize the callee.
    Often this can be achieved by supplying a "spurious" type parameter.
    Examples include replacing `higherorderfunction(f::Function, args...)` with `function higherorderfunction(f::F, args...) where F<:Function`,
    or `function getindex(A::MyArrayType{T,N}, idxs::Vararg{Int,N}) where {T,N}` instead of just `getindex(A::MyArrayType, idxs::Int...)`.
    (In the latter case, the `N` parameter is the crucial one: it forces specialization for a particular number of `Int` arguments.)

    This technique is not useful for the particular case we analyzed here, but it can be in other settings.

Making this simple 3-character fix eliminates that entire branch of the tree (a savings of 6 inference triggers).

### `eltype`s and reducing specialization in `broadcast`

Let's move on to the next entry:

```
julia> print_tree(itree.children[2])
MethodInstance for combine_eltypes(::Type, ::Tuple{Vector{Any}})
├─ MethodInstance for return_type(::Any, ::Any)
├─ MethodInstance for return_type(::Any, ::Any, ::UInt64)
├─ MethodInstance for return_type(::Core.Compiler.NativeInterpreter, ::Any, ::Any)
├─ MethodInstance for contains_is(::Core.SimpleVector, ::Any)
└─ MethodInstance for promote_typejoin_union(::Type{Main.OptimizeMe.Container})

julia> suggest(itree.children[2])
./broadcast.jl:905: regular invoke (perhaps precompile lotsa_containers() at OptimizeMe.jl:14)
├─ ./broadcast.jl:740: I've got nothing to say for MethodInstance for return_type(::Any, ::Any) consider `stacktrace(itrig)` or `ascend(itrig)`
├─ ./broadcast.jl:740: I've got nothing to say for MethodInstance for return_type(::Any, ::Any, ::UInt64) consider `stacktrace(itrig)` or `ascend(itrig)`
├─ ./broadcast.jl:740: I've got nothing to say for MethodInstance for return_type(::Core.Compiler.NativeInterpreter, ::Any, ::Any) consider `stacktrace(itrig)` or `ascend(itrig)`
├─ ./broadcast.jl:740: I've got nothing to say for MethodInstance for contains_is(::Core.SimpleVector, ::Any) consider `stacktrace(itrig)` or `ascend(itrig)`
└─ ./broadcast.jl:740: non-inferrable call, perhaps annotate combine_eltypes(f, args::Tuple) in Base.Broadcast at broadcast.jl:740 with type MethodInstance for promote_typejoin_union(::Type{Main.OptimizeMe.Container})
   If a noninferrable argument is a type or function, Julia's specialization heuristics may be responsible.
   immediate caller(s):
   3-element Vector{Base.StackTraces.StackFrame}:
    copy at broadcast.jl:905 [inlined]
    materialize at broadcast.jl:883 [inlined]
    lotsa_containers() at OptimizeMe.jl:14
```

While this tree is attributed to `broadcast`, you can see several references here to `OptimizeMe.jl:14`, which contains:

```julia
cs = Container.(list)
```

`Container.(list)` is a broadcasting operation, and once again we find that this has inferrability problems.
In this case, the initial suggestion "perhaps precompile `lotsa_containers`" is *not* helpful.
(The "regular invoke" just means that the initial call was one where inference knew all the argument types, and hence in principle might be precompilable, but from this tree we see that this broke down in some of its callees.)
Several children have no interpretation ("I've got nothing to say...").
Only the last one, "non-inferrable call", is (marginally) useful, it means that a call was made with arguments whose types could not be inferred.

!!! warning
    You should always view these suggestions skeptically.
    Often, they flag downstream issues that are better addressed at the source; frequently the best fix may be at a line a bit before the one identified in a trigger, or even in a dependent callee of a line prior to the flagged one.
    This is a product of the fact that *returning* a non-inferrable argument is not the thing that forces a new round of inference;
    it's *doing something* (making a specialization-worthy call) with the object of non-inferrable type that triggers a fresh entrance into inference.

How might we go about fixing this?
One hint is to notice that `itree.children[3]` through `itree.children[7]` also ultimiately derive from this one line of `OptimizeMe`,
but from a later line within `broadcast.jl` which explains why they are not bundled together with `itree.children[2]`.
May of these correspond to creating different `Container` types, for example:

```
└─ MethodInstance for restart_copyto_nonleaf!(::Vector{Main.OptimizeMe.Container}, ::Vector{Main.OptimizeMe.Container{Int64}}, ::Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1}, Tuple{Base.OneTo{Int64}}, Type{Main.OptimizeMe.Container}, Tuple{Base.Broadcast.Extruded{Vector{Any}, Tuple{Bool}, Tuple{Int64}}}}, ::Main.OptimizeMe.Container{UInt8}, ::Int64, ::Base.OneTo{Int64}, ::Int64, ::Int64)
   ├─ MethodInstance for Main.OptimizeMe.Container(::UInt16)
   ├─ MethodInstance for Main.OptimizeMe.Container(::Float32)
   ├─ MethodInstance for Main.OptimizeMe.Container(::Char)
   ├─ MethodInstance for Main.OptimizeMe.Container(::Vector{Int64})
   └─ MethodInstance for Main.OptimizeMe.Container(::Tuple{String, Int64})
```

We've created a `Container{T}` for each specific `T` of the objects in `list`.
In some cases, there may be good reasons for such specialization, and in such cases we just have to live with these inference failures.
However, in other cases the specialization might be detrimental to compile-time and/or runtime performance.
In such cases, we might decide to create them all as `Container{Any}`:

```julia
cs = Container{Any}.(list)
```

This 5-character change ends up eliminating 45 of our original 76 triggers.
Not only did we eliminate the triggers from broadcasting, but we limited the number of different `show(::IO, ::Container{T})`-`MethodInstance`s we need from later calls in `main`.

When the `Container` constructor does more complex operations, in some cases you may find that `Container{Any}(args...)` still gets specialized for different types of `args...`.
In such cases, you can create a special constructor that instructs Julia to avoid specialization in specific instances, e.g.,

```julia
struct Container{T}
    field1::T
    morefields...

    # This constructor permits specialization on `args`
    Container{T}(args...) where {T} = new{T}(args...)

    # For Container{Any}, we prevent specialization
    Container{Any}(@nospecialize(args...)) = new{Any}(args...)
end
```

If you're following along, the best option is to make these fixes and go back to the beginning, re-collecting `tinf` and processing the triggers.
We're down to 32 inference triggers.

### [Adding type-assertions](@id typeasserts)

If you've made the fixes above, the first child of `itree` is one for `show(::IOContext{Base.TTY}, ::MIME{Symbol("text/plain")}, ::Vector{Main.OptimizeMe.Container{Any}})`;
we'll skip that one for now, because it's a bit more sophisticated.
Right below it, we see

```
├─ MethodInstance for combine_eltypes(::Type, ::Tuple{Vector{Any}})
│  ├─ MethodInstance for return_type(::Any, ::Any)
│  ├─ MethodInstance for return_type(::Any, ::Any, ::UInt64)
```

and related nodes for `similar`, `copyto_nonleaf!`, etc., just as we saw above, so this looks like another case of broadcasting failure.
In this case, `suggest` quickly indicates that it's the broadcasting in

```julia
function contain_list(list)
    cs = Container.(list)
    return concat_string(cs...)
end
```

Now we know the problem: `main` creates `list = [2.718, "is jealous"]`,
a vector with different object types, and this leads to inference failures in broadcasting.
But wait, you might notice, `contain_concrete` gets called before `contain_list`, why doesn't it have a problem?
The reason is that `contain_concrete` and its callee, `concat_string`, provide opportunities for inference to handle each object in a separate argument;
the problems arise from bundling objects of different types into the same container.

There are several ways we could go about fixig this example:

- we could delete `contain_list` altogether and use `contain_concrete` for everything.
- we could try creating `list` as a tuple rather than a `Vector{Any}`; (small) tuples sometimes allow inference to succeed even when each element has a different type. This is as simple as changing `list = [2.718, "is jealous"]` to `list = (2.718, "is jealous")`, but whether it works to solve all your inference problems depends on the particular case.
- we could use external knowledge to annotate the types of the items in `list::Vector{Any}`.

Here we'll illustrate the last of these, since it's the only one that's nontrivial.
(It's also often a useful pattern in many real-world contexts, such as cases where you have a `Dict{String,Any}` but know something about the kinds of value-types associated with particular string keys.)
We could rewrite `contain_list` so it looks like this:

```julia
function contain_list(list)
    length(list) == 2 || throw(DimensionMismatch("list must have length 2"))
    item1 = list[1]::Float64
    item2 = list[2]::String
    return contain_concrete(item1, item2)     # or we could repeat the body of contain_concrete
end
```

The type-assertions tell inference that the corresponding items have the given types, and assist inference in cases where it has no mechanism to deduce the answer on its own.
Julia will throw an error if the type-assertion fails.
In some cases, a more forgiving option might be

```julia
item1 = convert(Float64, list[1])::Float64
```
which will attempt to convert `list[1]` to a `Float64`, and therefore handle a wider range of number types stored in the first element of `list`.
Believe it or not, both the `convert()` and the `::Float64` type-assertion are necessary:
since `list[1]` is of type `Any`, Julia will not be able to deduce which `convert` method will be used to perform the conversion, and it's always possible that someone has written a sloppy `convert` that doesn't return a value of the requested type.
Without that final `::Float64`, inference cannot simply assume that the result is a `Float64`.
The type-assert `::Float64` enforces the fact that you're expecting that `convert` call to actually return a `Float64`--it will error if it fails to do so, and it's this error that allows inference to be certain that for the purposes of any later code it must be a `Float64`.

Of course, this just trades one form of inference failure for another--the call to `convert` will be made by runtime dispatch--but this can nevertheless be a big win for two reasons:

- even though the `convert` call will be made by runtime dispatch, in this particular case `convert(Float64, ::Float64)` is already compiled in Julia itself.  Consequently it doesn't require a fresh run of inference.
- even in cases where the types are such that `convert` might need to be inferred & compiled, the type-assertion allows Julia to assume that `item1` is henceforth a `Float64`.  This makes it possible for inference to succeed for any code that follows.  When that's a large amount of code, the savings can be considerable.

Let's make that fix and also annotate the container type from `main`, `list = Any[2.718, "is jealous"]`.
Just to see how we're progressing, we start a fresh session and discover we're down to 20 triggers with just three direct branches.

### Vararg homogenization

We'll again skip over the `show` branches (they are two of the remaining three), and focus on this one:

```julia
julia> node = itree.children[2]
TriggerNode for MethodInstance for (::Base.var"#cat_t##kw")(::NamedTuple{(:dims,), Tuple{Val{1}}}, ::typeof(Base.cat_t), ::Type{Int64}, ::UnitRange{Int64}, ::Vararg{Any, N} where N) with 2 direct children

julia> print_tree(node)
MethodInstance for (::Base.var"#cat_t##kw")(::NamedTuple{(:dims,), Tuple{Val{1}}}, ::typeof(Base.cat_t), ::Type{Int64}, ::UnitRange{Int64}, ::Vararg{Any, N} where N)
├─ MethodInstance for cat_similar(::UnitRange{Int64}, ::Type, ::Tuple{Int64})
└─ MethodInstance for __cat(::Vector{Int64}, ::Tuple{Int64}, ::Tuple{Bool}, ::UnitRange{Int64}, ::Vararg{Any, N} where N)

julia> suggest(node)
./abstractarray.jl:1630: invoked callee is varargs (ignore this one, force-specialize the callee MethodInstance for (::Base.var"#cat_t##kw")(::NamedTuple{(:dims,), Tuple{Val{1}}}, ::typeof(Base.cat_t), ::Type{Int64}, ::UnitRange{Int64}, ::Vararg{Any, N} where N), or declare an umbrella type)
immediate caller(s):
1-element Vector{Base.StackTraces.StackFrame}:
 main() at OptimizeMe.jl:48
├─ ./abstractarray.jl:1636: caller is varargs (ignore this one, specialize the caller _cat_t(::Val{1}, ::Type{Int64}, ::UnitRange{Int64}, ::Vararg{Any, N} where N) at abstractarray.jl:1636, or improve inferrability of its caller)
│  immediate caller(s):
│  1-element Vector{Base.StackTraces.StackFrame}:
│   cat_t(::Type{Int64}, ::UnitRange{Int64}, ::Vararg{Any, N} where N; dims::Val{1}) at abstractarray.jl:1632
└─ ./abstractarray.jl:1640: caller is varargs (ignore this one, specialize the caller _cat_t(::Val{1}, ::Type{Int64}, ::UnitRange{Int64}, ::Vararg{Any, N} where N) at abstractarray.jl:1640, or improve inferrability of its caller)
   immediate caller(s):
   1-element Vector{Base.StackTraces.StackFrame}:
    cat_t(::Type{Int64}, ::UnitRange{Int64}, ::Vararg{Any, N} where N; dims::Val{1}) at abstractarray.jl:1632
```

Due to Julia's optimization and inlining, it's sometimes a bit hard to tell from these shortened displays where a particular trigger comes from.
(It turns out that this is finally the trigger we looked at in greatest detail in [method-based triggers](@ref methtrigs).)
In this case we extract the specific trigger and show the stacktrace:

```julia
julia> itrig = node.itrig
Inference triggered to call MethodInstance for (::Base.var"#cat_t##kw")(::NamedTuple{(:dims,), Tuple{Val{1}}}, ::typeof(Base.cat_t), ::Type{Int64}, ::UnitRange{Int64}, ::Vararg{Any, N} where N) from _cat (./abstractarray.jl:1630) inlined into MethodInstance for makeobjects() (/tmp/OptimizeMe.jl:39)

julia> stacktrace(itrig)
24-element Vector{Base.StackTraces.StackFrame}:
 exit_current_timer at typeinfer.jl:166 [inlined]
 typeinf(interp::Core.Compiler.NativeInterpreter, frame::Core.Compiler.InferenceState) at typeinfer.jl:208
 typeinf_ext(interp::Core.Compiler.NativeInterpreter, mi::Core.MethodInstance) at typeinfer.jl:835
 typeinf_ext_toplevel(interp::Core.Compiler.NativeInterpreter, linfo::Core.MethodInstance) at typeinfer.jl:868
 typeinf_ext_toplevel(mi::Core.MethodInstance, world::UInt64) at typeinfer.jl:864
 _cat at abstractarray.jl:1630 [inlined]
 #cat#127 at abstractarray.jl:1769 [inlined]
 cat at abstractarray.jl:1769 [inlined]
 vcat at abstractarray.jl:1698 [inlined]
 makeobjects() at OptimizeMe.jl:39
 main() at OptimizeMe.jl:48
 top-level scope at snoopi_deep.jl:53
 eval(m::Module, e::Any) at boot.jl:360
 eval_user_input(ast::Any, backend::REPL.REPLBackend) at REPL.jl:139
 repl_backend_loop(backend::REPL.REPLBackend) at REPL.jl:200
 start_repl_backend(backend::REPL.REPLBackend, consumer::Any) at REPL.jl:185
 run_repl(repl::REPL.AbstractREPL, consumer::Any; backend_on_current_task::Bool) at REPL.jl:317
 run_repl(repl::REPL.AbstractREPL, consumer::Any) at REPL.jl:305
 (::Base.var"#872#874"{Bool, Bool, Bool})(REPL::Module) at client.jl:387
 #invokelatest#2 at essentials.jl:707 [inlined]
 invokelatest at essentials.jl:706 [inlined]
 run_main_repl(interactive::Bool, quiet::Bool, banner::Bool, history_file::Bool, color_set::Bool) at client.jl:372
 exec_options(opts::Base.JLOptions) at client.jl:302
 _start() at client.jl:485
```

(You can also call `stacktrace` directly on `node`.)
It's the lines immediately following `typeinf_ext_toplevel` that need concern us:
you can see that the "last stop" on code we wrote here was `makeobjects() at OptimizeMe.jl:39`, after which it goes fairly deep into the concatenation pipeline before suffering an inference trigger at `_cat at abstractarray.jl:1630`.

In this case, the first hint is quite useful, if we know how to interpret it.
The `invoked callee is varargs` reassures us that the immediate caller, `_cat`, knows exactly which method it is calling (that's the meaning of the `invoked`).
The real problem is that it doesn't know how to specialize it.
The suggestion to `homogenize the arguments` is the crucial hint:
the problem comes from the fact that in

```julia
xs = [1:5; 7]
```

`1:5` is a `UnitRange{Int}` whereas `7` is an `Int`, and the fact that these are two different types prevents Julia from knowing how to specialize that varargs call.
But this is easy to fix, because the result will be identical if we write this as

```julia
xs = [1:5; 7:7]
```

in which case both arguments are `UnitRange{Int}`, and this allows Julia to specialize the varargs call.

!!! note
    It's generally a good thing that Julia doesn't specialize each and every varargs call, because the lack of specialization reduces latency.
    However, when you can homogenize the argument types and make it inferrable, you make it more worthy of precompilation, which is a different and ultimately more impactful approach to latency reduction.

### Defining `show` methods for custom types

Finally we are left with nodes that are related to `show`.
We'll temporarily skip the first of these and examine

```julia
julia> print_tree(node)
MethodInstance for show(::IOContext{Base.TTY}, ::MIME{Symbol("text/plain")}, ::Vector{Main.OptimizeMe.Object})
└─ MethodInstance for var"#sprint#386"(::IOContext{Base.TTY}, ::Int64, ::typeof(sprint), ::Function, ::Main.OptimizeMe.Object)
   └─ MethodInstance for sizeof(::Main.OptimizeMe.Object)
```

We'll use this as an excuse to point out that if you don't know how to deal with the root node of this (sub)tree, you can tackle later nodes:

```julia
julia> itrigsnode = flatten(node)
3-element Vector{InferenceTrigger}:
 Inference triggered to call MethodInstance for show(::IOContext{Base.TTY}, ::MIME{Symbol("text/plain")}, ::Vector{Main.OptimizeMe.Object}) from #38 (/home/tim/src/julia-master/usr/share/julia/stdlib/v1.6/REPL/src/REPL.jl:220) with specialization MethodInstance for (::REPL.var"#38#39"{REPL.REPLDisplay{REPL.LineEditREPL}, MIME{Symbol("text/plain")}, Base.RefValue{Any}})(::Any)
 Inference triggered to call MethodInstance for var"#sprint#386"(::IOContext{Base.TTY}, ::Int64, ::typeof(sprint), ::Function, ::Main.OptimizeMe.Object) from sprint##kw (./strings/io.jl:101) inlined into MethodInstance for alignment(::IOContext{Base.TTY}, ::Vector{Main.OptimizeMe.Object}, ::UnitRange{Int64}, ::UnitRange{Int64}, ::Int64, ::Int64, ::Int64) (./arrayshow.jl:68)
 Inference triggered to call MethodInstance for sizeof(::Main.OptimizeMe.Object) from _show_default (./show.jl:402) with specialization MethodInstance for _show_default(::IOContext{IOBuffer}, ::Any)

julia> itrig = itrigsnode[end]
Inference triggered to call MethodInstance for sizeof(::Main.OptimizeMe.Object) from _show_default (./show.jl:402) with specialization MethodInstance for _show_default(::IOContext{IOBuffer}, ::Any)
```

The stacktrace begins

```julia
julia> stacktrace(itrig)
35-element Vector{Base.StackTraces.StackFrame}:
 exit_current_timer at typeinfer.jl:166 [inlined]
 typeinf(interp::Core.Compiler.NativeInterpreter, frame::Core.Compiler.InferenceState) at typeinfer.jl:208
 typeinf_ext(interp::Core.Compiler.NativeInterpreter, mi::Core.MethodInstance) at typeinfer.jl:835
 typeinf_ext_toplevel(interp::Core.Compiler.NativeInterpreter, linfo::Core.MethodInstance) at typeinfer.jl:868
 typeinf_ext_toplevel(mi::Core.MethodInstance, world::UInt64) at typeinfer.jl:864
 _show_default(io::IOContext{IOBuffer}, x::Any) at show.jl:402
 show_default at show.jl:395 [inlined]
 show(io::IOContext{IOBuffer}, x::Any) at show.jl:390
 sprint(f::Function, args::Main.OptimizeMe.Object; context::IOContext{Base.TTY}, sizehint::Int64) at io.jl:103
⋮
```

You can see that `sprint` called `show` which called `_show_default`;
`_show_default` clearly needed to call `sizeof`.
The hint, in this case, suggests the impossible:

```
julia> suggest(itrig)
./show.jl:402: non-inferrable call, perhaps annotate _show_default(io::IO, x) in Base at show.jl:397 with type MethodInstance for sizeof(::Main.OptimizeMe.Object)
If a noninferrable argument is a type or function, Julia's specialization heuristics may be responsible.
immediate caller(s):
2-element Vector{Base.StackTraces.StackFrame}:
 show_default at show.jl:395 [inlined]
 show(io::IOContext{IOBuffer}, x::Any) at show.jl:390
```

Because `Base` doesn't know about `OptimizeMe.Object`, you could not add such an annotation, and it wouldn't be correct in the vast majority of cases.

As the name implies, `_show_default` is the fallback `show` method.
We can fix this by adding our own `show` method

```julia
Base.show(io::IO, o::Object) = print(io, "Object x: ", o.x)
```

to the module definition.
`Object` is so simple that this is slightly silly, but in more complex cases adding good `show` methods improves usability of your packages tremendously.
(SnoopCompile has many `show` specializations, and without them it would be practically unusable.)

When you do define a custom `show` method, you own it, so of course it will be precompilable.
So we've circumvented this particular issue.

### Creating "warmup" methods

Finally, it is time to deal with those long-delayed `show(::IOContext{Base.TTY}, ::MIME{Symbol("text/plain")}, ::T)` triggers and the triggers they inspire.
We have two of them, one for `T = Vector{Main.OptimizeMe.Container{Any}}` and one for `T = Vector{Main.OptimizeMe.Object}`.
Let's look at just the trigger associated with the first:

```
julia> itrig
Inference triggered to call MethodInstance for show(::IOContext{Base.TTY}, ::MIME{Symbol("text/plain")}, ::Vector{Main.OptimizeMeFixed.Container{Any}}) from #38 (/pathto/julia/usr/share/julia/stdlib/v1.6/REPL/src/REPL.jl:220) with specialization MethodInstance for (::REPL.var"#38#39"{REPL.REPLDisplay{REPL.LineEditREPL}, MIME{Symbol("text/plain")}, Base.RefValue{Any}})(::Any)
```

In this case we see that the method is `#38`.  This is a `gensym`, or generated symbol, indicating that the method was generated during Julia's lowering pass, and might indicate a macro, a `do` block or other anonymous function, the generator for a `@generated` function, etc.

!!! warning
    It's particularly worthwhile to improve inferrability for gensym-methods. The number assiged to a gensymmed-method may change as you or other developers modify the package (possibly due to changes at very difference source-code locations), and so any explicit `precompile` directives involving gensyms may not have a long useful life.

    But not all methods with `#` in their name are problematic: methods ending in `##kw` or that look like `##funcname#39` are *keyword* and *body* methods, respectively, for methods that accept keywords.  They can be obtained from the main method, and so `precompile` directives for such methods will not be outdated by incidental changes to the package.

`edit(itrig)` (or equivalently, `edit(node)` where `node` is a child of `itree`) takes us to this method in `Base`:

```julia
function display(d::REPLDisplay, mime::MIME"text/plain", x)
    x = Ref{Any}(x)
    with_repl_linfo(d.repl) do io
        io = IOContext(io, :limit => true, :module => Main::Module)
        get(io, :color, false) && write(io, answer_color(d.repl))
        if isdefined(d.repl, :options) && isdefined(d.repl.options, :iocontext)
            # this can override the :limit property set initially
            io = foldl(IOContext, d.repl.options.iocontext, init=io)
        end
        show(io, mime, x[])
        println(io)
    end
    return nothing
end
```

The generated method corresponds to the `do` block here.
The call to `show` comes from `show(io, mime, x[])`.
This implementation uses a clever trick, wrapping `x` in a `Ref{Any}(x)`, to prevent specialization of the method defined by the `do` block on the specific type of `x`.
This trick is designed to limit the number of `MethodInstance`s inferred for this `display` method.

Unfortunately, from the standpoint of precompilation we have something of a conundrum.
It turns out that this trigger corresponds to the first of the big red flames in the flame graph.
`show(::IOContext{Base.TTY}, ::MIME{Symbol("text/plain")}, ::Vector{Main.OptimizeMe.Container{Any}})` is not precompilable because `Base` owns the `show` method for `Vector`;
we might own the element type, but we're leveraging the generic machinery in `Base` and consequently it owns the method.
If these were all packages, you might request its developers to add a `precompile` directive, but that will work only if the package that owns the method knows about the relevant type.
In this situation, Julia's `Base` module doesn't know about `OptimizeMe.Container{Any}`, so we're stuck.

There are a couple of ways one might go about improving matters.
First, one option is that this should be changed in Julia itself: since the caller, `display`, has gone to some lengths to reduce specialization, it would be worth contemplating whether `show(io::IO, ::MIME"text/plain", X::AbstractArray)` should have a `@nospecialize` around `X`.
Here, we'll pursue a simple "cheat," one that allows us to directly precompile this method.
The trick is to link it, via a chain of backedges, to a method that our package owns:

```julia
# "Stub" callers for precompilability (we don't use this function for any real work)
function warmup()
    mime = MIME("text/plain")
    io = Base.stdout::Base.TTY
    # Container{Any}
    v = [Container{Any}(0)]
    show(io, mime, v)
    show(IOContext(io), mime, v)
    # Object
    v = [Object(0)]
    show(io, mime, v)
    show(IOContext(io), mime, v)
    return nothing
end

precompile(warmup, ())
```

We handled not just `Vector{Container{Any}}` but also `Vector{Object}`, since that turns out to correspond to the other wide block of red bars.
If you make this change, start a fresh session, and recreate the flame graph, you'll see that the wide red flames are gone:

![flamegraph-OptimizeMeFixed](assets/flamegraph-OptimizeMeFixed.png)


!!! info
    It's worth noting that this `warmup` method needed to be carefully written to succeed in its mission. `stdout` is not inferrable (it's a global that can be replaced by `redirect_stdout`), so we needed to annotate its type. We also might have been tempted to use a loop, `for io in (stdout, IOContext(stdout)) ... end`, but inference needs a dedicated call-site where it knows all the types. ([Union-splitting](https://julialang.org/blog/2018/08/union-splitting/) can sometimes come to the rescue, but not if the list is long or elements non-inferrable.) The safest option is to make each call from a separate site in the code.

The next trigger, a call to `sprint` from inside `Base.alignment(io::IO, x::Any)`, could also be handled using this `warmup` trick, but the flamegraph says this call (also marked in red) isn't an expensive method to infer.  In such cases, it's fine to choose to leave it be.

### Implementing or requesting `precompile` directives in upstream packages

Of the remaining triggers (now numbering 14), the flamegraph indicates that the most expensive inference run is

```
Inference triggered to call MethodInstance for show(::IOContext{IOBuffer}, ::Float32) from _show_default (./show.jl:412) with specialization MethodInstance for _show_default(::IOContext{IOBuffer}, ::Any)
```

You can check that by listing the children of `ROOT` in order of `inclusive` time:

```julia
julia> nodes = sort(tinf.children; by=inclusive)
14-element Vector{SnoopCompileCore.InferenceTimingNode}:
 InferenceTimingNode: 0.000053/0.000053 on InferenceFrameInfo for ==(::Type, nothing::Nothing) with 0 direct children
 InferenceTimingNode: 0.000054/0.000054 on InferenceFrameInfo for sizeof(::Main.OptimizeMeFixed.Container{Any}) with 0 direct children
 InferenceTimingNode: 0.000061/0.000061 on InferenceFrameInfo for Base.typeinfo_eltype(::Type) with 0 direct children
 InferenceTimingNode: 0.000075/0.000380 on InferenceFrameInfo for show(::IOContext{IOBuffer}, ::Any) with 1 direct children
 InferenceTimingNode: 0.000445/0.000445 on InferenceFrameInfo for Pair{Symbol, DataType}(::Any, ::Any) with 0 direct children
 InferenceTimingNode: 0.000663/0.000663 on InferenceFrameInfo for print(::IOContext{Base.TTY}, ::String, ::String, ::Vararg{String, N} where N) with 0 direct children
 InferenceTimingNode: 0.000560/0.001049 on InferenceFrameInfo for Base.var"#sprint#386"(::IOContext{Base.TTY}, ::Int64, sprint::typeof(sprint), ::Function, ::Main.OptimizeMeFixed.Object) with 4 direct children
 InferenceTimingNode: 0.000441/0.001051 on InferenceFrameInfo for Pair(::Symbol, ::Type) with 1 direct children
 InferenceTimingNode: 0.000627/0.001140 on InferenceFrameInfo for Base.var"#sprint#386"(::IOContext{Base.TTY}, ::Int64, sprint::typeof(sprint), ::Function, ::Main.OptimizeMeFixed.Container{Any}) with 4 direct children
 InferenceTimingNode: 0.000321/0.001598 on InferenceFrameInfo for show(::IOContext{IOBuffer}, ::UInt16) with 4 direct children
 InferenceTimingNode: 0.000190/0.012516 on InferenceFrameInfo for show(::IOContext{IOBuffer}, ::Vector{Int64}) with 3 direct children
 InferenceTimingNode: 0.021179/0.033940 on InferenceFrameInfo for Base.Ryu.writeshortest(::Vector{UInt8}, ::Int64, ::Float32, ::Bool, ::Bool, ::Bool, ::Int64, ::UInt8, ::Bool, ::UInt8, ::Bool, ::Bool) with 29 direct children
 InferenceTimingNode: 0.000083/0.035496 on InferenceFrameInfo for show(::IOContext{IOBuffer}, ::Tuple{String, Int64}) with 1 direct children
 InferenceTimingNode: 0.000188/0.092555 on InferenceFrameInfo for show(::IOContext{IOBuffer}, ::Float32) with 1 direct children
```

You can see it's the most expensive remaining root, weighing in at nearly 100ms.
This method is defined in the `Base.Ryu` module,

```julia
julia> node = nodes[end]
InferenceTimingNode: 0.000188/0.092555 on InferenceFrameInfo for show(::IOContext{IOBuffer}, ::Float32) with 1 direct children

julia> Method(node)
show(io::IO, x::T) where T<:Union{Float16, Float32, Float64} in Base.Ryu at ryu/Ryu.jl:111
```

Now, we could add this to `warmup` and at least solve the inference problem.
However, on the flamegraph you might note that this is followed shortly by a couple of calls to `Ryu.writeshortest` (the third-most expensive to infer), followed by a long gap.
That hints that other steps, like native code generation, may be expensive.
Since these are base Julia methods, and `Float32` is a common type, it would make sense to file an issue or pull request that Julia should come shipped with these precompiled--that would cache not only the type-inference but also the native code, and thus represents a far more complete solution.

Later, we'll see how `parcel` can generate such precompile directives automatically, so this is not a step you need to implement entirely on your own.

Another `show` `MethodInstance`, `show(::IOContext{IOBuffer}, ::Tuple{String, Int64})`, seems too specific to be worth worrying about, so we call it quits here.

### [Advanced analysis: `ascend`](@id ascend-itrig)

One thing that hasn't yet been covered is that when you really need more insight, you can use `ascend`:

```julia
julia> itrig = itrigs[5]
Inference triggered to call MethodInstance for show(::IOContext{IOBuffer}, ::Float32) from _show_default (./show.jl:412) with specialization MethodInstance for _show_default(::IOContext{IOBuffer}, ::Any)

julia> ascend(itrig)
Choose a call for analysis (q to quit):
 >   show(::IOContext{IOBuffer}, ::Float32)
       _show_default(::IOContext{IOBuffer}, ::Any) at ./show.jl:412
         show_default at ./show.jl:395 => show(::IOContext{IOBuffer}, ::Any) at ./show.jl:390
           #sprint#386(::IOContext{Base.TTY}, ::Int64, ::typeof(sprint), ::Function, ::Main.OptimizeMeFixed.Container{Any}) at ./strings/io.jl:103
             sprint##kw at ./strings/io.jl:101 => alignment at ./show.jl:2528 => alignment(::IOContext{Base.TTY}, ::Vector{Main.OptimizeMeFixed.Container{Any}}, ::UnitRange{Int64}, ::UnitRange{Int64}, ::
               print_matrix(::IOContext{Base.TTY}, ::AbstractVecOrMat{T} where T, ::String, ::String, ::String, ::String, ::String, ::String, ::Int64, ::Int64) at ./arrayshow.jl:197
                 print_matrix at ./arrayshow.jl:169 => print_array at ./arrayshow.jl:323 => show(::IOContext{Base.TTY}, ::MIME{Symbol("text/plain")}, ::Vector{Main.OptimizeMeFixed.Container{Any}}) at ./a
                   (::REPL.var"#38#39"{REPL.REPLDisplay{REPL.LineEditREPL}, MIME{Symbol("text/plain")}, Base.RefValue{Any}})(::Any) at /home/tim/src/julia-master/usr/share/julia/stdlib/v1.6/REPL/src/REPL
                     with_repl_linfo(::Any, ::REPL.LineEditREPL) at /home/tim/src/julia-master/usr/share/julia/stdlib/v1.6/REPL/src/REPL.jl:462
v                      display(::REPL.REPLDisplay, ::MIME{Symbol("text/plain")}, ::Any) at /home/tim/src/julia-master/usr/share/julia/stdlib/v1.6/REPL/src/REPL.jl:213

```

`ascend` was covered in much greater detail in [fixing invalidations](@ref invalidations), and you can read about using it on that page.
Here, one twist is that some lines contain content like

```
show_default at ./show.jl:395 => show(::IOContext{IOBuffer}, ::Any) at ./show.jl:390
```

This indicates that `show_default` was inlined into `show`.
`ascend` needs the full non-inlined `MethodInstance` to descend into, so the tree only includes such nodes.
However, within Cthulhu you can toggle optimization and thereby descend into some of these inlined method, or see the full consequence of their inlining into the caller.

## [A note on analyzing test suites](@id test-suites)

If you're doing a package analysis, it's convenient to use the package's `runtests.jl` script as a way to cover much of the package's functionality.
SnoopCompile has a couple of enhancements designed to make it easier to ignore inference triggers that come from the test suite itself.
First, `suggest.(itrigs)` may show something like this:

```
 ./broadcast.jl:1315: inlineable (ignore this one)
 ./broadcast.jl:1315: inlineable (ignore this one)
 ./broadcast.jl:1315: inlineable (ignore this one)
 ./broadcast.jl:1315: inlineable (ignore this one)
```

This indicates a broadcasting operation in the `@testset` itself.
Second, while it's a little dangerous (because `suggest` cannot entirely be trusted), you can filter these out:

```julia
julia> itrigsel = [itrig for itrig in itrigs if !isignorable(suggest(itrig))];

julia> length(itrigs)
222

julia> length(itrigsel)
71
```

While there is some risk of discarding triggers that provide clues about the origin of other triggers (e.g., they would have shown up in the same branch of the `trigger_tree`), the shorter list may help direct your attention to the "real" issues.

## Results from the improvements

An improved version of `OptimizeMe` can be found in `OptimizeMeFixed.jl` in the same directory.
Let's see where we stand:

```julia
julia> tinf = @snoopi_deep OptimizeMeFixed.main()
3.14 is great
2.718 is jealous
...
 Object x: 7
InferenceTimingNode: 0.888522055/1.496965222 on InferenceFrameInfo for Core.Compiler.Timings.ROOT() with 15 direct children
```

We've substantially shrunk the overall inclusive time from 2.68s to about 1.5s.
Some of this came from our single `precompile` directive, for `warmup`.
But even more of it came from limiting specialization (using `Container{Any}` instead of `Container`) and by making some results easier on type-inference (e.g., our changes for the `vcat` pipeline).

On the next page, we'll wrap all this up with more explicit `precompile` directives.
