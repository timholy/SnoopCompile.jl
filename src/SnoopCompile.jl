module SnoopCompile

using SnoopCompileCore
export @snoopc
# More exports are defined below in the conditional loading sections
isdefined(SnoopCompileCore, Symbol("@snoopi")) &&
if isdefined(SnoopCompileCore, Symbol("@snoopi_deep"))

end
if isdefined(SnoopCompileCore, Symbol("@snoopr"))

end

using Core: MethodInstance, CodeInfo
using Serialization, OrderedCollections
import YAML  # For @snoopl
using Requires

# Parcel Regex
const anonrex = r"#{1,2}\d+#{1,2}\d+"         # detect anonymous functions
const kwrex = r"^#kw##(.*)$|^#([^#]*)##kw$"   # detect keyword-supplying functions
const kwbodyrex = r"^##(\w[^#]*)#\d+"         # detect keyword body methods
const genrex = r"^##s\d+#\d+$"                # detect generators for @generated functions
const innerrex = r"^#[^#]+#\d+"               # detect inner functions

# Parcel
include("parcel_snoopc.jl")

if isdefined(SnoopCompileCore, Symbol("@snoopi"))
    include("parcel_snoopi.jl")
    export @snoopi
end

if isdefined(SnoopCompileCore, Symbol("@snoopi_deep"))
    include("parcel_snoopi_deep.jl")
    export @snoopi_deep, flamegraph, flatten_times, accumulate_by_source, runtime_inferencetime
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

# Write
include("write.jl")

function __init__()
    if isdefined(SnoopCompile, :runtime_inferencetime)
        @require PyPlot = "d330b81b-6aea-500a-939a-2ce795aea3ee" include("visualizations.jl")
    end
end

end # module
