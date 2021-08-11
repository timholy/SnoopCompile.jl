# [Tutorial on the foundations](@id tutorial)

Certain concepts and types will appear repeatedly, so it's worth
spending a little time to familiarize yourself at the outset.
You can find a more expansive version of this page in [this blog post](https://julialang.org/blog/2021/01/precompile_tutorial/).

## `MethodInstance`s, type-inference, and backedges

Our first goal is to understand how code connects together.
We'll try some experiments using the following:

```julia
double(x::Real) = 2x
calldouble(container) = double(container[1])
calldouble2(container) = calldouble(container)
```

```@meta
DocTestSetup = quote
   double(x::Real) = 2x
   calldouble(container) = double(container[1])
   calldouble2(container) = calldouble(container)
end
```

Let's create a `container` and run this code:

```jldoctest tutorial
julia> c64 = [1.0]
1-element Vector{Float64}:
 1.0

julia> calldouble2(c64)
2.0
```

Using the [MethodAnalysis](https://github.com/timholy/MethodAnalysis.jl) package, we can get some insights into how Julia represents this code and its compilation dependencies:

```jldoctest tutorial; setup=:(calldouble2(c64))
julia> using MethodAnalysis

julia> mi = methodinstance(double, (Float64,))
MethodInstance for double(::Float64)

julia> using AbstractTrees

julia> print_tree(mi)
MethodInstance for double(::Float64)
└─ MethodInstance for calldouble(::Vector{Float64})
   └─ MethodInstance for calldouble2(::Vector{Float64})
```

This indicates that the result for type-inference on `calldouble2(::Vector{Float64})` depended on the result for `calldouble(::Vector{Float64})`, which in turn depended on `double(::Float64)`.

Now let's create a new container, one with abstract element type, so that Julia's type-inference cannot accurately predict the type of elements in the container:

```jldoctest tutorial
julia> cabs = AbstractFloat[1.0f0]      # put a Float32 in a Vector{AbstractFloat}
1-element Vector{AbstractFloat}:
 1.0f0

julia> calldouble2(cabs)
2.0f0
```

Now let's look at the available instances:

```jldoctest tutorial; setup=:(calldouble2(c64); calldouble2(cabs))
julia> mis = methodinstances(double)
3-element Vector{Core.MethodInstance}:
 MethodInstance for double(::Float64)
 MethodInstance for double(::AbstractFloat)
 MethodInstance for double(::Float32)

julia> print_tree(mis[1])
MethodInstance for double(::Float64)
└─ MethodInstance for calldouble(::Vector{Float64})
   └─ MethodInstance for calldouble2(::Vector{Float64})

julia> print_tree(mis[2])
MethodInstance for double(::AbstractFloat)

julia> print_tree(mis[3])
MethodInstance for double(::Float32)
```

`double(::Float64)` has backedges to `calldouble` and `calldouble2`, but the second two do not because `double` was only called via runtime dispatch. However, `calldouble` has backedges to `calldouble2`

```julia
julia> mis = methodinstances(calldouble)
2-element Vector{Core.MethodInstance}:
 MethodInstance for calldouble(::Vector{Float64})
 MethodInstance for calldouble(::Vector{AbstractFloat})

julia> print_tree(mis[1])
MethodInstance for calldouble(::Vector{Float64})
└─ MethodInstance for calldouble2(::Vector{Float64})

julia> print_tree(mis[2])
MethodInstance for calldouble(::Vector{AbstractFloat})
└─ MethodInstance for calldouble2(::Vector{AbstractFloat})
```

because `Vector{AbstractFloat}` is a concrete type, whereas `AbstractFloat` is not.

If we create `c32 = [1.0f0]` and then `calldouble2(c32)`, we would also see backedges from `double(::Float32)` all the way back to `calldouble2(::Vector{Float32})`.

## Precompilation

During *package precompilation*, Julia creates a `*.ji` file typically stored in `.julia/compiled/v1.x/`, where `1.x` is your version of Julia.
Your `*.ji` file might just have definitions of constants, types, and methods, but optionally you can also include the results of type-inference.
This happens automatically if you run code while your package is being built, but generally the recommended procedure is to add *precompile directives*.

Let's turn the example above into a package. In a fresh session,

```julia
(@v1.6) pkg> generate SnoopCompileDemo
  Generating  project SnoopCompileDemo:
    SnoopCompileDemo/Project.toml
    SnoopCompileDemo/src/SnoopCompileDemo.jl

julia> open("SnoopCompileDemo/src/SnoopCompileDemo.jl", "w") do io
           write(io, """
           module SnoopCompileDemo

           double(x::Real) = 2x
           calldouble(container) = double(container[1])
           calldouble2(container) = calldouble(container)

           precompile(calldouble2, (Vector{Float32},))
           precompile(calldouble2, (Vector{Float64},))
           precompile(calldouble2, (Vector{AbstractFloat},))

           end
           """)
       end
282

julia> push!(LOAD_PATH, "SnoopCompileDemo/")
4-element Vector{String}:
 "@"
 "@v#.#"
 "@stdlib"
 "SnoopCompileDemo/"

julia> using SnoopCompileDemo
[ Info: Precompiling SnoopCompileDemo [44c70eed-03a3-46c0-8383-afc033fb6a27]

julia> using MethodAnalysis

julia> methodinstances(SnoopCompileDemo.double)
3-element Vector{Core.MethodInstance}:
 MethodInstance for double(::Float32)
 MethodInstance for double(::Float64)
 MethodInstance for double(::AbstractFloat)
```

Because of those `precompile` statements, the `MethodInstance`s exist after loading the package even though we haven't run the code in this session--not because it precompiled them when the package loaded, but because they were precompiled during the `Precompiling SnoopCompileDemo...` phase, stored to `*.ji` file, and then reloaded whenever we use the package.
You can also verify that the same backedges get created as when we ran this code interactively above.

By having these `MethodInstance`s "pre-loaded" we can save some of the time needed to run type-inference: not much time in this case because the code is so simple, but for more complex methods the savings can be substantial.

This code got cached in `SnoopCompileDemo.ji`. It's worth noting that even though the `precompile` directive got issued from this package, it might save `MethodInstances` for methods defined in other packages.
For example, Julia does not come pre-built with the inferred code for `Int * Float32`: in a fresh session,

```julia
julia> using MethodAnalysis

julia> mi = methodinstance(*, (Int, Float32))

```
returns `nothing` (the `MethodInstance` doesn't exist), whereas if we've loaded `SnoopCompileDemo` then

```julia
julia> mi = methodinstance(*, (Int, Float32))
MethodInstance for *(::Int64, ::Float32)

julia> mi.def
*(x::Number, y::Number) in Base at promotion.jl:322
```

So even though the method is defined in `Base`, because `SnoopCompileDemo` needed this code it got stashed in `SnoopCompileDemo.ji`.

*The ability to cache `MethodInstance`s from code defined in other packages or libraries is fundamental to latency reduction; however, it has significant limitations.*  Most crucially, `*.ji` files can only hold code they "own," either:

- to a method defined in the package
- through a chain of backedges to methods owned by the package

If we add

```julia
precompile(*, (Int, Float16))
```

to the definition of `SnoopCompileDemo.jl`, nothing happens:

```julia
julia> mi = methodinstance(*, (Int, Float16))
                                                 # nothing
```

because there is no "chain of ownership" to `SnoopCompileDemo`.
Consequently, we can't precompile methods defined in other modules in and of themselves; we can only do it if those methods are linked by backedges to this package.

Because backedges are created during successful type-inference, the consequence is that *precompilation works better when type inference succeeds.*
For some packages, time invested in improving inferrability can make your `precompile` directives work better.

```@meta
DocTestSetup = nothing
```
