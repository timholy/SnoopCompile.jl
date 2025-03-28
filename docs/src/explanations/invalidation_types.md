# Invalidation types

There are two broad classes of invalidated targets, under `backedges` and `mt_backedges`. `backedges` occur whenever well-inferred code that dispatched to a "fallback method" was invalidated because a more specific method applicable to those argument types was defined. Example:

```
f(::Any) = nothing      # fallback method
g(x) = f(x)             # caller of f
g(1)                    # force compilation of both `g(::Int)` and `f(::Int)`
f(x::Int) = 2x          # dispatch from `g(::Int)` is supplanted by a more specific method
```

The main approach for avoiding such invalidations is to define the more-specific method before any code using the fallback definition is compiled. Sometimes this can be difficult or impossible to achieve, particularly if the callee has a definition for `Any`. If the fallback is a bit more specific than `Any`, one strategy is to avoid any overlap. For example, if `f` has a fallback `f(::Integer)`, and you want to define your own custom type and a method of `f` for it, you can avoid invalidations if your new type does not subtype `Integer`. However, you have to decide whether the features you lose by avoiding subtyping are worth the reduced number of invalidations.

`mt_backedges` invalidations are generally easier to fix. They result when the inferred call-signature `sig` for the callee `f` in a caller `g` may not have an applicable method. There are several ways they can arise:

- poorly-inferred code: if you've defined `f(x::Number)` but at a callsite in `g` the argument supplied to `f` can only be inferred as `Any`, so that `sig = Tuple{typeof(f), Any}`.
- a call `f(a, b)` when only `f(x)` has been defined
- a call `fundefined(x)` where `fundefined` does not exist
