module SnoopCompile

using Serialization, OrderedCollections

export timesum  # @snoopi and @snoopc are exported from their files of definition

const anonrex = r"#{1,2}\d+#{1,2}\d+"         # detect anonymous functions
const kwrex = r"^#kw##(.*)$|^#([^#]*)##kw$"   # detect keyword-supplying functions
const kwbodyrex = r"^##(\w[^#]*)#\d+"         # detect keyword body methods
const genrex = r"^##s\d+#\d+$"                # detect generators for @generated functions
const innerrex = r"^#[^#]+#\d+"               # detect inner functions

if VERSION >= v"1.2.0-DEV.573"
    include("snoopi.jl")
    include("parcel_snoopi.jl")
end
include("snoopc.jl")
include("parcel_snoopc.jl")

include("write.jl")
include("bot.jl")

end # module
