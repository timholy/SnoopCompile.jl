module StaleA

stale(x) = rand(1:8)
stale(x::Int) = length(digits(x))

not_stale(x::String) = first(x)

use_stale(c) = stale(c[1]) + not_stale("hello")
build_stale(x) = use_stale(Any[x]) # deliberately defeat inference so `use_stale` is vulnerable to invalidation

# force precompilation
build_stale(37)
stale('c')

end
