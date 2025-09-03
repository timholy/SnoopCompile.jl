module InvalidE

using InvalidA
using InvalidB
using InvalidC

InvalidA.f(::Int8) = 5
# Base.delete_method(which(InvalidA.f, (Int,)))   # method deletion is not allowed during package precompilation

end # module InvalidE
