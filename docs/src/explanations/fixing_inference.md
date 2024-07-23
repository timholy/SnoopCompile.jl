# Techniques for fixing inference problems

Here we assume you've dug into your code with a tool like Cthulhu, and want to know how to fix some of the problems that you discover. Below is a collection of specific cases and some tricks for handling them.

Note that there is also a [tutorial on fixing inference](@ref inferrability) that delves into advanced topics.

## Adding type annotations

### Using concrete types

Defining variables like `list = []` can be convenient, but it creates a `list` of type `Vector{Any}`. This prevents inference from knowing the type of items extracted from `list`. Using `list = String[]` for a container of strings, etc., is an excellent fix. When in doubt, check the type with `isconcretetype`: a common mistake is to think that `list_of_lists = Array{Int}[]` gives you a vector-of-vectors, but

```jldoctest
julia> isconcretetype(Array{Int})
false
```

reminds you that `Array` requires a second parameter indicating the dimensionality of the array. (Or use `list_of_lists = Vector{Int}[]` instead, as `Vector{Int} === Array{Int, 1}`.)

Many valuable tips can be found among [Julia's performance tips](https://docs.julialang.org/en/v1/manual/performance-tips/), and readers are encouraged to consult that page.

### Working with non-concrete types

In cases where invalidations occur, but you can't use concrete types (there are indeed many valid uses of `Vector{Any}`),
you can often prevent the invalidation using some additional knowledge.
One common example is extracting information from an [`IOContext`](https://docs.julialang.org/en/v1/manual/networking-and-streams/#IO-Output-Contextual-Properties-1) structure, which is roughly defined as

```julia
struct IOContext{IO_t <: IO} <: AbstractPipe
    io::IO_t
    dict::ImmutableDict{Symbol, Any}
end
```

There are good reasons that `dict` uses a value-type of `Any`, but that makes it impossible for the compiler to infer the type of any object looked up in an `IOContext`.
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

If the return type is one of a small number of possibilities (generally three or fewer), you can annotate the return type with `Union{...}`. This is generally advantageous only when the intersection of what inference already knows about the types of a variable and the types in the `Union` results in an concrete type.

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

## Inferrable field access for abstract types

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
As a consequence, Julia's inference may not realize that `d.width` returns an `Int`.

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

## Fixing `Core.Box`

[Julia issue 15276](https://github.com/JuliaLang/julia/issues/15276) is one of the more surprising forms of inference failure; it is the most common cause of a `Core.Box` annotation.
If other variables depend on the `Box`ed variable, then a single `Core.Box` can lead to widespread inference problems.
For this reason, these are also among the first inference problems you should tackle.

Read [this explanation of why this happens and what you can do to fix it](https://docs.julialang.org/en/v1/manual/performance-tips/#man-performance-captured).
If you are directed to find `Core.Box` inference triggers via [`suggest`](@ref), you may need to explore around the call site a bit--
the inference trigger may be in the closure itself, but the fix needs to go in the method that creates the closure.

Use of `ascend` is highly recommended for fixing `Core.Box` inference failures.

## Handling edge cases

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
