module StaleA

stale(x) = rand(1:8)
stale(x::Int) = length(digits(x))

not_stale(x::String) = first(x)

use_stale(c) = stale(c[1]) + not_stale("hello")
build_stale(x) = use_stale(Any[x])

# force precompilation
build_stale(37)
stale('c')

end
