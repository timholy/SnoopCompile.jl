module StaleC

using StaleA

StaleA.stale(x::String) = length(x)         # piracy is great (but not required) for triggering invalidations
call_buildstale(x) = StaleA.build_stale(x)  # linking build_stale to a method in this module ensures caching

call_buildstale("hey")                      # forces re/precompilation of `StaleA.use_stale(::Vector{Any})`

end # module
