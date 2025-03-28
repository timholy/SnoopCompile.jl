# Invalidation types

There are two broad classes of invalidated targets, under `backedges` and `mt_backedges`. `backedges` occur whenever well-inferred code that dispatched to a "fallback method" was invalidated because a more specific method applicable to those argument types was defined. Example:

```
f(::Any) = nothing      # fallback method
g(x) = f(x)             # caller of f
g(1)                    # force compilation of both `g(::Int)` and `f(::Int)`
f(x::Int) = 2x          # dispatch from `g(::Int)` is supplanted by a more specific method
```

The main approach for avoiding such invalidations is to define the more-specific method before any code using the fallback definition is compiled. Sometimes this can be difficult or impossible to achieve, particularly if the callee has a definition for `Any`. If the callee is a bit more specific, then one strategy is to ensure that any new methods accept types that do not intersect with the argument types of existing methods. For example, if `f` has a fallback `f(::Integer)`, and you want to define your own custom type and a method of `f` for it, you can avoid invalidations if your new type does not subtype `Integer`.

`mt_backedges` invalidations are generally easier to fix. They result when the inferred call-signature `sig` at the callsite is wider than any available method, introducing some risk that there is no method that can cover this call. There are several ways they can arise:

- poorly-inferred code: if you've defined `f(::Number)` but in the caller inference fails completely, so that `sig = Tuple{typeof(f), Any}`.
- an explicit `invoke` with too-wide `argtypes`, e.g., `invoke(f, Tuple{Any}, x)` when the only definition of `f` is `f(::Number)`.
- a function 