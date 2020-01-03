module Reachable

module ModuleA
export RchA
struct RchA end
end # ModuleA

module ModuleB
using Reachable.ModuleA
export rchb
rchb(::RchA) = "hello"
f(a) = 1
end # ModuleB

end # Reachable
