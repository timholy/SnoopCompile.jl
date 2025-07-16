# Invalidation classes

[`invalidation_trees`](@ref) returns two broad classes of invalidated targets in `backedges` and `mt_backedges`.
To understand the difference, let's introduce a new term: we say that a callee method *covers* a call if it can accept all possible types used in that call. Consider this example:

```julia
f(x::Integer) = false
g1(x::Signed) = f(x)    # `f(::Integer)` always covers this call
g2(x::Number) = f(x)    # `f(::Integer)` may not cover this call
```

`g1` will only ever be called for `Signed` inputs, and because `Signed <: Integer`, the method of `f` fully covers the call in `g1`. In contrast, `g2` can be called for any `Number` type, and since `Number` is not a subtype of `Integer`, `f` may not cover the entire call.

With this understanding, the difference is straightforward: `backedges`-class invalidations are when there is exactly one applicable method and it fully covers the call. `mt_backedges`-class invalidations are for anything else. In such cases, Julia may need to scan the method table (the `mt` in `mt_backedges`) of the function in order to determine which method, if any, might be applicable.

This helps explain why `mt_backedges` invalidations are more likely to arise from poor inference: poor inference "widens" the argument types and thus makes it more likely that a call is unlikely to be covered by exactly one method. It's still possible to get a `backedges`-class invalidation from poor inference:

```julia
g3(x::Ref{Any}) = f(x[]::Signed)
```

guarantees that our method of `f` covers the call, even though we can't predict with precision what type `x[]` will return. Thus if you invalidate the compiled code of `g3` by defining a new method for `f(x::Signed)`, you'll get a `backedges`-class invalidation.
