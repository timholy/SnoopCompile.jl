# Tutorial on `@snoop_invalidations`

Invalidations are a product of unexpected interactions between packages, or between packages and Base Julia. We'll illustrate invalidations by creating two packages, where loading the second package invalidates some methods in the first one. This example is inspired by the [darts problem](https://exercism.org/tracks/julia/exercises/darts) on Exercism.

While [PkgTemplates](https://github.com/JuliaCI/PkgTemplates.jl) is recommended for creating packages, to keep dependencies minimal here we'll just use the basic capabilities in `Pkg`.
While you would generally use an editor to create the package code, here we'll do it programmatically so that you can just copy/paste the code below and expect to get the same outcome.

## Add SnoopCompileCore, SnoopCompile, and helper packages to your environment

Here, we'll add these packages to your [default environment](https://pkgdocs.julialang.org/v1/environments/). You can, of course, perform this analysis in a different environment if you prefer.

```@repl
using Pkg
Pkg.add(["SnoopCompileCore", "SnoopCompile", "AbstractTrees", "Cthulhu"])
```

SnoopCompileCore is a tiny package with no dependencies; it's used for collecting data, and it has been designed in such a way that it cannot cause any invalidations of its own.
SnoopCompile is a much larger package that performs analysis on the data collected by SnoopCompileCore; loading SnoopCompile can (and does) trigger invalidations.
Consequently, you're urged to always collect data with just SnoopCompileCore loaded,
and wait to load SnoopCompile until after you've finished collecting the data.

[Cthulhu](https://github.com/JuliaDebug/Cthulhu.jl) is a companion package you'll want for any analysis of invalidations. Here we'll also use the [AbstractTrees](https://github.com/JuliaCollections/AbstractTrees.jl) package for simple printing.

## Creating the demonstration packages

Here are the steps executed by the code below:
- navigate to a temporary directory and create both packages
- make the first package (`ScoreDarts`) depend on [PrecompileTools](https://github.com/JuliaLang/PrecompileTools.jl) (we're interested in reducing latency!)
- make the second package (`MoreDarts`) depend on the first one (`ScoreDarts`)

```@repl tutorial-invalidations
cd(mktempdir())
using Pkg
Pkg.generate("ScoreDarts");
Pkg.activate("ScoreDarts")
Pkg.add("PrecompileTools")
Pkg.generate("MoreDarts");
Pkg.activate("MoreDarts")
Pkg.develop(PackageSpec(path=joinpath(pwd(), "ScoreDarts")));
```

Now it's time to create the code for `ScoreDarts`. The code below does the following:
- creates different `TargetCircle`s that one can hit
- assigns the correct score for each target circle
- creates a convenience function that parses a sequence of characters, converts them into target circles, and then adds the scores
- precompiles the code to reduce latency on first use

```@repl tutorial-invalidations
write(joinpath("ScoreDarts", "src", "ScoreDarts.jl"), """
    module ScoreDarts

    using PrecompileTools

    @enum TargetCircle outer middle inner

    score(circle::TargetCircle) = circle == outer  ? 1 :
                                  circle == middle ? 5 : 10

    # Add up the scores (this is much simpler than Julia's own `sum(score, turns)`)
    function tallyscores(turns)
        s = 0
        for t in turns
            s += score(t)
        end
        return s
    end

    # Create a dictionary that maps characters to circles
    const chardict = Dict{Char,Any}('o' => outer,
                                    'm' => middle,
                                    'i' => inner)

    # Create a function that translates 'o', 'm', and 'i' into their different circles
    # and then adds the scores
    function scoresequence(chars)
        turns = []
        for c in chars
            push!(turns, chardict[c])
        end
        return tallyscores(turns)
    end

    # Precompile `scoresequence`:
    @compile_workload begin
        scoresequence("omi")
    end

    end
    """)
```

`MoreDarts` will extend `ScoreDarts` in an important way: we acknowledge that maybe the target wasn't hit at all, in which case the score is zero. Because we can't add to the `TargetCircle` `@enum`, let's just create a new type:

```@repl tutorial-invalidations
write(joinpath("MoreDarts", "src", "MoreDarts.jl"), """
    module MoreDarts

    using ScoreDarts

    struct MissedTarget end
    const miss = MissedTarget()

    # Add a new `score` method:
    ScoreDarts.score(::MissedTarget) = 0

    # Use `'x'` to indicate a miss
    push!(ScoreDarts.chardict, 'x' => miss)

    end
    """)
```

Now we're ready! As a

## Recording invalidations

Here are the steps executed by the code below
- load `SnoopCompileCore`
- load `MoreDarts` while recording invalidations
- load `SnoopCompile` and `AbstractTrees` for analysis

```@repl tutorial-invalidations
using SnoopCompileCore
invs = @snoop_invalidations using MoreDarts;
using SnoopCompile, AbstractTrees
```

## Analyzing invalidations

Now we're ready to see what, if anything, got invalidated:

```@repl tutorial-invalidations
trees = invalidation_trees(invs)
```

This has only one "tree" of invalidations, from a single cause described in the top line:
adding the new method `score(::MoreDarts.MissedTarget)`.

`trees` is a `Vector` so we can index it; we can also extract the list of "root" targets for invalidation, and then see what happened using `@ascend`:

```@repl tutorial-invalidations
sig, root = trees[1].mt_backedges[end];
sig
```

!!! note
    `mt_backedges` stands for "method-table backedges." SnoopCompile has a second type of invalidation, just called `backedges`. With these, there is no `sig`, and so you'll use just `root = trees[i].backedges[j]`.

Here you can see the problematic `sig`nature: `score` was called on an object of (inferred) type `Any`. Because Julia couldn't infer the actual type, this code was vulnerable, and insertion of the new `score` method "exploited" this vulnerability.

`root` itself indicates that `tallyscores` is the "victim" of invalidation, but this is not the full extent of what got invalidated:

```@repl tutorial-invalidations
print_tree(root)
```

We can see that the invalidation propagated all the way up to `scoresequence(::String)`.
In general, roots with lots of "children" deserve the greatest attention.

In most cases, Cthulhu's `ascend` provides a more useful tool for identifying the cause of invalidations:

```julia
julia> using Cthulhu

julia> ascend(root)
Choose a call for analysis (q to quit):
 >   tallyscores(::Vector{Any})
       scoresequence(::String)
```

This is an interactive REPL-menu, described more completely (including a Youtube video) at [ascend](https://github.com/JuliaDebug/Cthulhu.jl?tab=readme-ov-file#usage-ascend).

## Why the invalidations occur

Evidently, `turns` is a `Vector{Any}`, and this means that `tallyscores` can't guess what kind of objects will come out of it, and thus it can't guess what kind of objects are passed into `score`. However, Julia notices that `score` only supports `TargetCircle`s, and thus it *speculatively* guesses that all the objects in `turns` will likely be `TargetCircle`s. It thus compiles the code to (1) check that indeed the object really is a `TargetCircle`, and (2) call `score` for a `TargetCircle`.

This speculative compilation based on what methods and types are "in the world" at the time of compilation (sometimes called *world-splitting*) can be a useful performance optimization. Looking up applicable methods while the code is running can be slow, and any work that can be done ahead of time can lead to significant savings.

Unfortunately, when the "world" changes--through the addition of a new `score` method for a new type--the old compiled code is no longer valid. The code must be recompiled, accounting for this new possibility, before it can be safely run again. Thus, invalidations are a product of compilation happening in a "smaller" world than the one in the user's running session.

## Fixing invalidations

In broad strokes, there are two ways to prevent invalidation. The first is to improve the quality of type-inference. For example, in

```julia
    function scoresequence(chars)
        turns = []
```
that unqualified `[]` is what makes `turns` a `Vector{Any}`. If we didn't need to allow extensions of `scoresequence`, we could have said `turns = TargetCircle[]` and that would have required that all elements of `turns` be `TargetCircles`. This would "bullet-proof" `scoresequence` from invalidation, at the cost of preventing extensions such as `MoreDarts`. (The package developer(s) get to decide whether this is a good or bad thing--in this case, one could argue that the failure to account for `miss` is a bug in `ScoreDarts` and is better fixed there.)

!!! tip
    Many vulnerabilities can be fixed by improving inference. In complex code, it's easy to unwittingly write things in ways that defeat Julia's type inference. Not only does fixing the inference problem prevent invalidation, it typically makes your code run faster too. When fixing invalidations, your first thought should always be, "can I improve inference in this code without making compromises in its functionality?"

The second option is to prevent Julia's speculative optimization: one could replace the direct call to `score` with an `invokelatest(score, turn)`:

```julia
function tallyscores(turns)
        s = 0
        for t in turns
            s += invokelatest(score, t)
        end
        return s
    end
```

This forces Julia to always look up the appropriate method of `score` while the code is running, and thus prevents the speculative optimizations that leave the code vulnerable to invalidation. If you re-run the above demonstration, using `invokelatest` as shown, then `trees` will be empty--no invalidations! However, the cost is that your code may run somewhat more slowly.

More details about fixing invalidations can be found in [Techniques for fixing inference problems](@ref).
