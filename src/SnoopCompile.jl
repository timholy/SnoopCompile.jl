"""
SnoopCompile allows you to collect and analyze data on actions of Julia's compiler.

The capabilities depend on your version of Julia; in general, the capabilities that
require more recent Julia versions are also the most powerful and useful. When possible,
you should prefer them above the more limited tools available on earlier versions.

## All Julia versions

- `@snoopc`: record Julia's code generation
- `SnoopCompile.read`: parse data collected from `@snoopc`
- `SnoopCompile.parcel`: split precompile statements into modules/packages
- `SnoopCompile.write`: write module-specific precompile files (")

## At least Julia 1.2

- `@snoopi`: record entrances to Julia's type-inference (`parcel` and `write` work on these data, too)

## At least Julia 1.6

### Invalidations

- `@snoopr`: record invalidations
- `uinvalidated`: collect unique method invalidations from `@snoopr`
- `invalidation_trees`: organize invalidation data into trees
- `filtermod`: select trees that invalidate methods in particular modules
- `findcaller`: find a path through invalidation trees reaching a particular method
- `ascend`: interactive analysis of an invalidation tree

### LLVM

- `@snoopl`: record data about the actions of LLVM, the library used to generate native code
- `read_snoopl`: parse data collected by `@snoopl`

### "Deep" data on inference

- `@snoopi_deep`: record more extensive data about type-inference (`parcel` and `write` work on these data, too)
- `flamegraph`: prepare a visualization from `@snoopi_deep`
- `flatten`: reduce the tree format recorded by `@snoopi_deep` to list format
- `accumulate_by_source`: aggregate list items by their source
- `inference_triggers`: extract data on the triggers of inference
- `callerinstance`, `callingframe`, `skiphigherorder`, and `InferenceTrigger`: manipulate stack frames from `inference_triggers`
- `ascend`: interactive analysis of an inference-triggering call chain
- `runtime_inferencetime`: profile-guided deoptimization
"""
module SnoopCompile

using SnoopCompileCore
export @snoopc
# More exports are defined below in the conditional loading sections

using Core: MethodInstance, CodeInfo
using InteractiveUtils
using Serialization
using Printf
using OrderedCollections
import YAML  # For @snoopl
using Requires

# Parcel Regex
const anonrex = r"#{1,2}\d+#{1,2}\d+"         # detect anonymous functions
const kwrex = r"^#kw##(.*)$|^#([^#]*)##kw$"   # detect keyword-supplying functions
const kwbodyrex = r"^##(\w[^#]*)#\d+"         # detect keyword body methods
const genrex = r"^##s\d+#\d+$"                # detect generators for @generated functions
const innerrex = r"^#[^#]+#\d+"               # detect inner functions

# This is for SnoopCompile's own directives. You don't want to call this from packages because then
# SnoopCompile becomes a dependency of your package. Instead, make sure that `writewarnpcfail` is set to `true`
# in `SnoopCompile.write` and a copy of this macro will be placed at the top
# of your precompile files.
macro warnpcfail(ex::Expr)
    modl = __module__
    file = __source__.file === nothing ? "?" : String(__source__.file)
    line = __source__.line
    quote
        $(esc(ex)) || @warn """precompile directive
     $($(Expr(:quote, ex)))
 failed. Please report an issue in $($modl) (after checking for duplicates) or remove this directive.""" _file=$file _line=$line
    end
end

# Parcel
include("parcel_snoopc.jl")

if isdefined(SnoopCompileCore, Symbol("@snoopi"))
    include("parcel_snoopi.jl")
    export @snoopi
end

if isdefined(SnoopCompileCore, Symbol("@snoopi_deep"))
    include("parcel_snoopi_deep.jl")
    include("deep_demos.jl")
    export @snoopi_deep, exclusive, inclusive, flamegraph, flatten, accumulate_by_source, collect_for, runtime_inferencetime, staleinstances
    export InferenceTrigger, inference_triggers, callerinstance, callingframe, skiphigherorder, trigger_tree, suggest, isignorable
    export report_callee, report_caller, report_callees
end

if isdefined(SnoopCompileCore, Symbol("@snoopl"))
    export @snoopl
end
# To support reading of results on an older Julia version, this isn't conditional
include("parcel_snoopl.jl")
export read_snoopl

if isdefined(SnoopCompileCore, Symbol("@snoopr"))
    include("invalidations.jl")
    export @snoopr, uinvalidated, invalidation_trees, filtermod, findcaller, ascend
end

if isdefined(SnoopCompileCore, Symbol("@snoopr")) && isdefined(SnoopCompileCore, Symbol("@snoopi_deep"))
    include("invalidation_and_inference.jl")
    export precompile_blockers
end

# Write
include("write.jl")

function __init__()
    if isdefined(SnoopCompile, :runtime_inferencetime)
        @require PyPlot = "d330b81b-6aea-500a-939a-2ce795aea3ee" include("visualizations.jl")
    end
    if isdefined(SnoopCompile, :inference_triggers)
        @require JET = "c3a54625-cd67-489e-a8e7-0a5a0ff4e31b" include("jet_integration.jl")
    end
end

end # module
