# Information for SnoopCompile developers

## Invalidations

### Capturing invalidation logs

Julia itself handles (in)validation when you define (or delete) methods and load packages. Julia's internal machinery provides the option of recording these invalidation decisions to a log, which is just a `Vector{Any}`. Currently (as of Julia 1.12) there are two independent logs:

- for method insertion and deletion (i.e., new methods invalidating old code), logging is handled in Julia's `src/gf.c`. You enable it with `logmeths = ccall(:jl_debug_method_invalidation, Any, (Cint,), true)` and pass a final argument of `false` to turn it off.
- for validating precompiled code during package loading (i.e., "new" code being invalidated by old methods), logging is handled in Julia's `base/staticdata.jl`. You enable it with `logedges = Base.StaticData.debug_method_invalidation(true)` and pass `false` to turn it off.

In both cases, the log will initially be empty, but subsequent activity (defining or deleting methods, or loading packages) may add entries.

SnoopCompileCore's `@snoop_invalidation` just turns on these logging streams, executes the user's block of code, turns off logging, and returns the captured log streams.

### Interpreting invalidation logs

The definitive source for interpreting these two logging streams is Julia's own code; the documentation below may be outdated by future changes in Julia. (Such changes have happened repeatedly over the course of Julia's development.) If you have even a shred of doubt about whether any of this is (still) correct, check Julia's code.

For both logging streams, a single decision typically results in appending multiple entries to the log. These decisions come with a string (the *tag*) documenting the origin of each entry. In general, each distinct mechanism by which invalidations can occur should have its own unique tag. Often these correspond to specific lines in the source code.

#### method logs

Let `trigger::Method` indicate an added or deleted method for function `f`. If defining/deleting this method would change how one or more `caller::MethodInstance`s of the corresponding function would dispatch, those `caller`s must be invalidated. Such events can result in a cascade of invalidations of code that directly or indirectly called `trigger` or less-specific methods of the same function. The order in which these invalidations appear in the log stream is as follows:

2. Backedges of `callee` below, encoded as a tree where links are specified as `(caller::MethodInstance, depth::Int32)` pairs.
  `depth=1` typically corresponds to an inferrable caller. `depth=0` corresponds to a potentially-missing callee (at the time of compilation), and will be followed by `calleesig::Type`. (If the called function had potentially-applicable methods, `calleesig` will not be a subtype of any of their signatures.) corresponds to the root (though no entry with `depth=0` is written), and sequential increases in `depth` indicate a traversal through branches. If `depth` decreases, this indicates the start of a new branch from the parent with depth `depth-1`.
1. `(callee::MethodInstance, tag)` pairs that were directly affected by change in dispatch.
3. Possibly,

After all such `callee` branches are complete, the `(trigger::Method, tag)` event that initiated the entire set of invalidations pair is logged.

The interpretation of the tags is as follows:

- `"jl_method_table_disable"`: the `trigger` with the same tag was deleted (`Base.delete_method`)
- `"jl_method_table_insert"`: the `trigger` with the same tag was added (`function f(...) end`)
- `(callee::MethodInstance, "invalidate_mt_cache")`: a method-table cache for runtime dispatch was invalidated by a method insertion. At sites of runtime dispatch, Julia will maintain local method tables of the most common call targets to make dispatch more efficient. Since runtime dispatch involves real-time method lookup anyway, this form of invalidation is not serious, and a detailed listing is suppressed by SnoopCompile's printing behavior. These are always followed (eventually) by a `(trigger::Method, "jl_method_table_insert")` pair.

#### edge logs

Since edge logs are populated during package loading, we'll use `PkgDep` to indicate a package that is a dependency for `PkgUser`. (`PkgUser`'s `Project.toml` might list `PkgDep` in its `[deps]` section, or it might be an indirect dependency.)
Invalidation events result in the insertion of 3 or 4 items in `logedges`. The tag is always the second item. They take one of the following forms:

- `(def::Method, "method_globalref", codeinst::CodeInstance, nothing)`: method `def` in `PkgUser` references `PkgDep.SomeObject` (which might be `const` data, a type, etc.), but the binding for `SomeObject` has been modified since `PkgUser` was compiled. `codeinst`, which holds a compiled specialization of `def`, needs to be recompiled.
- `(edge::Union{MethodInstance,Type,Core.Binding}, "insert_backedges_callee", codeinst::CodeInstance, matches::Union{Vector{Method},Nothing})`: `edge` was selected as a dispatch target (a "callee") of `codeinst`, but new method(s) listed in `matches` now supersede it in dispatch specificity. There are 3 or 4 sub-cases:
  * `edge::MethodInstance` indicates a known target at the time of compilation
  * `edge::Type` represents either
    + `Tuple{typeof(f), argtypes...}` for a poorly-inferred or `invoke`d call for which the target selected at compilation time is no longer valid (`matches` will be `nothing`)
    + a signature of a known function for which no appropriate method had yet been defined at the time of compilation. `matches` lists methods that now apply. (These are not technically invalidations, and are suppressed by SnoopCompile's printing behavior.)
  * `edge::Core.Binding` indicates a target that was unknown at the time of compilation, and `matches` will be `nothing`.
- `(child::CodeInstance, "verify_methods", cause::CodeInstance)`: `cause` is an invalidated dependency of `child` (i.e., invalidations that cascade from the proximal source).
