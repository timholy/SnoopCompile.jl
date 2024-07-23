# Package roles and alternatives

## SnoopCompile

SnoopCompileCore is a tiny package with no dependencies; it's used for collecting data, and it has been designed in such a way that it cannot cause any invalidations of its own. Collecting data on invalidations and inference with SnoopCompileCore is the only way you can be sure you are observing the "native state" of your code.

## SnoopCompile

SnoopCompile is a much larger package that performs analysis on the data collected by SnoopCompileCore; loading SnoopCompile can (and does) trigger invalidations.
Consequently, you're urged to always collect data with just SnoopCompileCore loaded,
and wait to load SnoopCompile until after you've finished collecting the data.

## Cthulhu

[Cthulhu](https://github.com/JuliaDebug/Cthulhu.jl) is a companion package that gives deep insights into the origin of invalidations or inference failures.

## AbstractTrees

[AbstractTrees](https://github.com/JuliaCollections/AbstractTrees.jl) is the one package in this list that can be both a "workhorse" and a developer tool. SnoopCompile uses it mostly for pretty-printing.

## JET

[JET](https://github.com/aviatesk/JET.jl) is perhaps the main alternative to SnoopCompile. The packages have some overlap in what they can tell you about your code, but their mechanisms of action are fundamentally different:

- JET is a "static analyzer," which means that it analyzes the code itself. JET can tell you about inference failures (runtime dispatch) much like SnoopCompile, with one major advantage: SnoopCompileCore requires you to use `@snoop_inference` in a fresh session and omits information about any callees that have been compiled previously, whereas JET's `@report_opt` provides exhaustive information about the entire *inferable* callgraph (i.e., the part of the callgraph that inference can predict from the initial call).

- SnoopCompileCore collects data by watching normal inference at work. On code that hasn't been compiled previously, this can yield results similar to JET's, with a different major advantage: SnoopCompileCore can "see through" runtime dispatch, and provide insights about callees that are invisible to JET.

Perhaps surprisingly, combining JET and SnoopCompile can provide insights that are difficult to obtain with either package in isolation. See the [Tutorial on JET integration](@ref).