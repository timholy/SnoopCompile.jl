module StaleC

using StaleA

StaleA.stale(x::String) = length(x)
call_buildstale(x) = StaleA.build_stale(x)

call_buildstale("hey")

end # module
