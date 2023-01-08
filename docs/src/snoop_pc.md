# SnoopPrecompile

SnoopPrecompile provides a macro, `@precompile_all_calls`, which precompiles every call on its first usage.
The key feature of `@precompile_all_calls` is that it intercepts all callees (including those made by runtime dispatch) and, on Julia 1.8 and higher, allows you to precompile the callee even if it comes from a different module (e.g., `Base` or a different package).

Statements that occur inside a `@precompile_all_calls` block are executed only if the package is being actively precompiled;
it does not run when the package is loaded, nor if you're running Julia with `--compiled-modules=no`.

SnoopPrecompile also exports `@precompile_setup`, which you can use to create data for use inside a `@precompile_all_calls` block. Like `@precompile_all_calls`, this code only runs when you are precompiling the package, but it does not
necessarily result in the "setup" code being stored in the package precompile file.

Here's an illustration of how you might use `@precompile_all_calls` and `@precompile_setup`:

```julia
module MyPackage

using SnoopPrecompile    # this is a small dependency

struct MyType
    x::Int
end
struct OtherType
    str::String
end

@precompile_setup begin
    # Putting some things in `setup` can reduce the size of the
    # precompile file and potentially make loading faster.
    list = [OtherType("hello"), OtherType("world!")]
    @precompile_all_calls begin
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

In this case, the "top level" calls were fully inferrable, so there are no entries on this list
that were called by runtime dispatch. Thus, here you could have gotten the same result with manual
`precompile` directives.
The key advantage of `@precompile_all_calls` is that it works even if the functions you're calling
have runtime dispatch.

If you want to see the list of calls that will be precompiled, navigate to the `MyPackage` folder and use

```julia
julia> using SnoopPrecompile

julia> SnoopPrecompile.verbose[] = true   # runs the block even if you're not precompiling, and print precompiled calls

julia> include("src/MyPackage.jl");
```

Once you set up `SnoopPrecompile`, try your package and see if it reduces the time to first execution,
using the same workload you put inside the `@precompile_all_calls` block.

If you're happy with the results, you're done! If you want deeper verification of whether it worked as
expected, or if you suspect problems, then the rest of SnoopCompile provides additional tools.
Potential sources of trouble include invalidation (see [`@snoopr`](@ref) and related) and omission of
intended calls from inside the `@precompile_all_calls` block (see [`@snoopi_deep`](@ref) and related).

!!! note
    `@precompile_all_calls` works by monitoring type-inference. If the code was already inferred
    prior to `@precompile_all_calls` (e.g., from prior usage), you might omit any external
    methods that were called via runtime dispatch.

    You can use multiple `@precompile_all_calls` blocks if you need to interleave "setup" code with
    code that you want precompiled.
    You can use `@snoopi_deep` to check for any (re)inference when you use the code in your package.
    To fix any specific problems, you can combine `@precompile_all_calls` with manual `precompile` directives.

One can reduce the cost of precompilation for selected packages using the `Preferences.jl` based mechanism and the `skip_precompile` key:
```julia
using SnoopPrecompile, Preferences
set_preferences!(SnoopPrecompile, "skip_precompile" => ["PackageA", "PackageB"])
```

After restarting julia, the `@precompile_all_calls` and `@precompile_setup` workloads will be disabled (locally) for `PackageA` and `PackageB`.
