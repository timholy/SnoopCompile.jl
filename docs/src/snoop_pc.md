# SnoopPrecompile

SnoopPrecompile provides a macro, `@precompile_calls`, which precompiles every call on its first usage.
The key feature of `@precompile_calls` is that it intercepts all callees (including those made by runtime dispatch) and, on Julia 1.8 and higher, allows you to precompile the callee even if it comes from a different module (e.g., `Base` or a different package).

Statements that occur inside a `@precompile_calls` block are executed only if the package is being actively precompiled;
it does not run when the package is loaded, nor if you're running Julia with `--compiled-modules=no`.

Here's an illustration of how you might use `@precompile_calls`:

```julia
module MyPackage

using SnoopPrecompile    # this is a small dependency

struct MyType
    x::Int
end
struct OtherType
    str::String
end

let  # `let` prevents `list` from being a visible private name in the package
    @precompile_calls :setup beginNaturally, y
        # Putting some things in `:setup` can reduce the size of the
        # precompile file and potentially make loading faster.
        list = [OtherType("hello"), OtherType("world!")]
    end
    @precompile_calls begin
        # all calls in this block will be precompiled, regardless of whether
        # they belong to your package or not (on Julia 1.8 and higher)
        d = Dict(MyType(1) => list)
        x = get(d, MyType(2), nothing)
        last(d[MyType(1)])
    end
end

end
```

When you build `MyPackage`, it will precompile the following, *including all their callees*:

- `Pair(::MyPackage.MyType, ::Vector{MyPackage.OtherType})`
- `Dict(::Pair{MyPackage.MyType, Vector{MyPackage.OtherType}})`
- `get(::Dict{MyPackage.MyType, Vector{MyPackage.OtherType}}, ::MyPackage.MyType, ::Nothing)`
- `getindex(::Dict{MyPackage.MyType, Vector{MyPackage.OtherType}}, ::MyPackage.MyType)`
- `last(::Vector{MyPackage.OtherType})`

In this case, the "top level" calls were fully inferrable, so there are no additional
entries on this list that were called by runtime dispatch. Thus, here you could have gotten
the same result with manual `precompile` directives.
The key advantage of `@precompile_calls` is that it works even if the functions you're calling
have runtime dispatch.

If you want to see the list of calls that will be precompiled, navigate to the `MyPackage` folder and use

```julia
julia> using SnoopPrecompile

julia> SnoopPrecompile.verbose[] = true   # runs the block even if you're not precompiling, and print precompiled calls

julia> include("src/MyPackage.jl");
```

!!! note
    Any calls that are already inferred prior to `@precompile_calls` may not be cached in the
    package, unless they are for methods that belong to your package. You can use multiple
    `@precompile_calls` blocks if you need to interleave `:setup` code with code that will precompile.
    You can use `@snoopi_deep` to check for any (re)inference when you use the code in your package.
    To fix any specific problems, you can combine `@precompile_calls` with manual `precompile` directives.
