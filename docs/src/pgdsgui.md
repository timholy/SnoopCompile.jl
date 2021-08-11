# [Profile-guided despecialization](@id pgds)

As indicated in the [workflow](@ref), one of the important early steps is to evaluate and potentially adjust method specialization.
Each specialization (each `MethodInstance` with different argument types) costs extra inference and code-generation time,
so while specialization often improves runtime performance, that has to be weighed against the cost in latency.
There are also cases in which [overspecialization can hurt both run-time and compile-time performance](https://docs.julialang.org/en/v1/manual/performance-tips/#The-dangers-of-abusing-multiple-dispatch-(aka,-more-on-types-with-values-as-parameters)).
Consequently, an analysis of specialization can be a powerful tool for improving package quality.

`SnoopCompile` ships with an interactive tool, [`pgdsgui`](@ref), short for "Profile-guided despecialization."
The name is a reference to a related technique, [profile-guided optimization](https://en.wikipedia.org/wiki/Profile-guided_optimization) (PGO).
Both PGO and PGDS use rutime profiling to help guide decisions about code optimization.
PGO is often used in languages whose default mode is to avoid specialization, whereas PGDS seems more appropriate for
a language like Julia which specializes by default.
While PGO is sometimes an automatic part of the compiler that optimizes code midstream during execution, PGDS is a tool for making static changes in code.
Again, this seems appropriate for a language where specialization typically happens prior to the first execution of the code.

## Using the PGDS graphical user interface

To illustrate the use of PGDS, we'll examine an example in which some methods get specialized for hundreds of types.
To keep this example short, we'll create functions that operate on types themselves.

!!! note
    For a `DataType` `T`, `T.name` returns a `Core.TypeName`, and `T.name.name` returns the name as a `Symbol`.
    `Base.unwrap_unionall(T)` preserves `DataType`s as-is, but converts a `UnionAll` type into a `DataType`.

```julia
"""
    spelltype(T::Type)

Spell out a type's name, one character at a time.
"""
function spelltype(::Type{T}) where T
    name = Base.unwrap_unionall(T).name.name
    str = ""
    for c in string(name)
        str *= c
    end
    return str
end

"""
    mappushes!(f, dest, src)

Like `map!` except it grows `dest` by one for each element in `src`.
"""
function mappushes!(f, dest, src)
    for item in src
        push!(dest, f(item))
    end
    return dest
end

mappushes(f, src) = mappushes!(f, [], src)
```

There are two stages to PGDS: first (and preferrably starting in a fresh Julia session), we profile type-inference:

```julia
julia> using SnoopCompile

julia> Ts = subtypes(Any);  # get a long list of different types

julia> tinf = @snoopi_deep mappushes(spelltype, Ts)
InferenceTimingNode: 4.476700/5.591207 on InferenceFrameInfo for Core.Compiler.Timings.ROOT() with 587 direct children
```

Then, *in the same session*, profile the runtime:

```
julia> using Profile

julia> @profile mappushes(spelltype, Ts);
```

Typically, it's best if the workload here is reflective of a "real" workload (test suites often are not), so that you
get a realistic view of where your code spends its time during actual use.

Now let's launch the PDGS GUI:

```julia
julia> import PyPlot        # the GUI is dependent on PyPlot, must load it before the next line

julia> mref, ax = pgdsgui(tinf);
```

You should see something like this:

![pgdsgui](assets/pgds_spec.png)

In this graph, each dot corresponds to a single method; for this method, we plot inference time (vertical axis) against the run time (horizontal axis).
The coloration of each dot encodes the number of specializations (the number of distinct `MethodInstance`s) for that method;
by default it even includes the number of times the method was inferred for specific constants ([constant propagation](https://en.wikipedia.org/wiki/Constant_folding)), although you can exclude those cases using the `consts=false` keyword.
Finally, the edge of each dot encodes the fraction of time spent on runtime dispatch (aka, type-instability), with black indicating
0% and bright red indicating 100%.

In this plot, we can see that no method runs for more than 0.01 seconds, whereas some methods have an aggregate inference time of up to 1s.
Overall, inference-time dominates this plot.
Moreover, for the most expensive cases, the number of specializations is in the hundreds or thousands.

To learn more about *what* is being specialized, just click on one of the dots; if you choose the upper-left dot (the one with highest inference time), you should see something like this in your REPL:

```julia
spelltype(::Type{T}) where T in Main at REPL[1]:6 (586 specializations)
```

This tells you the method corresponding to this dot. Moreover, `mref` (one of the outputs of `pgdsgui`) holds this method:

```julia
julia> mref[]
spelltype(::Type{T}) where T in Main at REPL[1]:6
```

What are the specializations, and how costly was each?

```julia
julia> collect_for(mref[], tinf)
586-element Vector{SnoopCompileCore.InferenceTimingNode}:
 InferenceTimingNode: 0.003486/0.020872 on InferenceFrameInfo for spelltype(::Type{T}) where T with 7 direct children
 InferenceTimingNode: 0.003281/0.003892 on InferenceFrameInfo for spelltype(::Type{AbstractArray}) with 2 direct children
 InferenceTimingNode: 0.003349/0.004023 on InferenceFrameInfo for spelltype(::Type{AbstractChannel}) with 2 direct children
 InferenceTimingNode: 0.000827/0.001154 on InferenceFrameInfo for spelltype(::Type{AbstractChar}) with 5 direct children
 InferenceTimingNode: 0.003326/0.004070 on InferenceFrameInfo for spelltype(::Type{AbstractDict}) with 2 direct children
 InferenceTimingNode: 0.000833/0.001159 on InferenceFrameInfo for spelltype(::Type{AbstractDisplay}) with 5 direct children
⋮
 InferenceTimingNode: 0.000848/0.001160 on InferenceFrameInfo for spelltype(::Type{YAML.Span}) with 5 direct children
 InferenceTimingNode: 0.000838/0.001148 on InferenceFrameInfo for spelltype(::Type{YAML.Token}) with 5 direct children
 InferenceTimingNode: 0.000833/0.001150 on InferenceFrameInfo for spelltype(::Type{YAML.TokenStream}) with 5 direct children
 InferenceTimingNode: 0.000809/0.001126 on InferenceFrameInfo for spelltype(::Type{YAML.YAMLDocIterator}) with 5 direct children
```

So we can see that one `MethodInstance` for each type in `Ts` was generated.

If you see a list of `MethodInstance`s, and the first is extremely costly in terms of inclusive time, but all the rest are not, then you might not need to worry much about over-specialization:
your inference time will be dominated by that one costly method (often, the first time the method was called), and the fact that lots of additional specializations were generated may not be anything to worry about.
However, in this case, the distribution of time is fairly flat, each contributing a small portion to the overall time.
In such cases, over-specialization may be a problem.

### Reducing specialization with `@nospecialize`

How might we change this? To reduce the number of specializations of `spelltype`, we use `@nospecialize` in its definition:

```julia
function spelltype(@nospecialize(T::Type))
    name = Base.unwrap_unionall(T).name.name
    str = ""
    for c in string(name)
        str *= c
    end
    return str
end
```

!!! warning
    `where` type-parameters force specialization, regardless of `@nospecialize`: in `spelltype(@nospecialize(::Type{T})) where T`, the `@nospecialize` has no impact and you'll get full specialization on `T`.
    Instead, use `@nospecialize(T::Type)` as shown.

If we now rerun that demo, you should see a plot of the same kind as shown above, but with different costs for each dot.
The differences are best appreciated comparing them side-by-side ([`pgdsgui`](@ref) allows you to specify a particular axis into
which to plot):

![pgdsgui-compare](assets/pgds_compareplots.png)

The results with `@nospecialize` are shown on the right. You can see that:

- Now, the most expensive-to-infer method is <0.01s (formerly it was ~1s)
- No method has more than 2 specializations

Moreover, our runtimes (post-compilation) really aren't very different, both in the ballpark of a few millseconds (you can check with `@btime` from BenchmarkTools to be sure).

In total, we've reduced compilation time approximately 50× without appreciably hurting runtime perfomance.
Reducing specialization, when appropriate, can often yield your biggest reductions in latency.

!!! tip
    When you add `@nospecialize`, sometimes it's beneficial to compensate for the loss of inferrability by adding some type assertions.
    This topic will be discussed in greater detail in the next section, but for the example above we can improve runtime performance by annotating the return type of `Base.unwrap_unionall(T)`: `name = (Base.unwrap_unionall(T)::DataType).name.name`.
    Then, later lines in `spell` know that `name` is a `Symbol`.

    With this change, the unspecialized variant outperforms the specialized variant in *both compile-time and run-time*.
    The reason is that the specialized variant of `spell` needs to be called by runtime dispatch, whereas for the unspecialized variant there's only one `MethodInstance`, so its dispatch is handled at compile time.

### Argument standardization

While not immediately relevant to the example above, a very important technique that falls within the domain of reducing specialization is *argument standardization*: instead of

```julia
function foo(x, y)
    # some huge function, slow to compile, and you'd prefer not to compile it many times for different types of x and y
end
```

consider whether you can safely write this as

```julia
function foo(x::X, y::Y)   # X and Y are concrete types
    # some huge function, but the concrete typing ensures you only compile it once
end
foo(x, y) = foo(convert(X, x)::X, convert(Y, y)::Y)   # this allows you to still call it with any argument types
```

The "standardizing method" `foo(x, y)` is short and therefore quick to compile, so it doesn't really matter if you compile many different instances.

!!! tip
    In `convert(X, x)::X`, the final `::X` guards against a broken `convert` method that fails to return an object of type `X`.
    Without it, `foo(x, y)` might call itself in an infinite loop, ultimately triggering a StackOverflowError.
    StackOverflowErrors are a particularly nasty form of error, and the typeassert ensures that you get a simple `TypeError` instead.

    In other contexts, such typeasserts would also have the effect of fixing inference problems even if the type of `x` is not well-inferred (this will be discussed in more detail [later](@ref typeasserts)), but in this case dispatch to `foo(x::X, y::Y)` would have ensured the same outcome.

There are of course cases where you can't implement your code in this way: after all, part of the power of Julia is the ability of generic methods to "do the right thing" for a wide variety of types. But in cases where you're doing a standard task, e.g., writing some data to a file, there's really no good reason to recompile your `save` method for a filename encoded as a `String` and again for a `SubString{String}` and again for a `SubstitutionString` and again for an `AbstractString` and ...: after all, the core of the `save` method probably isn't sensitive to the precise encoding of the filename.  In such cases, it should be safe to convert all filenames to `String`, thereby reducing the diversity of input arguments for expensive-to-compile methods.

If you're using `pgdsgui`, the cost of inference and the number of specializations may guide you to click on specific dots; `collect_for(mref[], tinf)` then allows you to detect and diagnose cases where argument standardization might be helpful.

You can do the same analysis without `pgdsgui`. The opportunity for argument standardization is often facilitated by looking at, e.g.,

```julia
julia> tms = accumulate_by_source(flatten(tinf));  # collect all MethodInstances that belong to the same Method

julia> t, m = tms[end-1]        # the ones towards the end take the most time, maybe they are over-specialized?
(0.4138147, save(filename::AbstractString, data) in SomePkg at /pathto/SomePkg/src/SomePkg.jl:23)

julia> methodinstances(m)       # let's see what specializations we have
7-element Vector{Core.MethodInstance}:
 MethodInstance for save(::String, ::Vector{SomePkg.SomeDataType})
 MethodInstance for save(::SubString{String}, ::Vector{SomePkg.SomeDataType})
 MethodInstance for save(::AbstractString, ::Vector{SomePkg.SomeDataType})
 MethodInstance for save(::String, ::Vector{SomePkg.SomeDataType{SubString{String}}})
 MethodInstance for save(::SubString{String}, ::Array)
 MethodInstance for save(::String, ::Vector{var"#s92"} where var"#s92"<:SomePkg.SomeDataType)
 MethodInstance for save(::String, ::Array)
```

In this case we have 7 `MethodInstance`s (some of which are clearly due to poor inferrability of the caller) when one might suffice.
