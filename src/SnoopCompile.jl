module SnoopCompile

using Serialization

const anonrex = r"#{1,2}\d+#{1,2}\d+"         # detect anonymous functions
const kwrex = r"^#kw##(.*)$|^#([^#]*)##kw$"   # detect keyword-supplying functions
const kwbodyrex = r"^##(\w[^#]*)#\d+"         # detect keyword body methods
const genrex = r"^##s\d+#\d+$"                # detect generators for @generated functions

if VERSION >= v"1.2.0-DEV.573"
    include("snoopi.jl")
    include("parcel_snoopi.jl")
end
include("snoopc.jl")
include("parcel_snoopc.jl")

include("write.jl")

end # module
