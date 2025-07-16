module InvalidD

using InvalidA
using InvalidB
using InvalidC
using PrecompileTools

@compile_workload begin
    InvalidA.callscallsf(1)
    InvalidA.alsocallsf(1)
    InvalidA.invokesfs(1)
    # We now have enough methods of `InvalidA.f` to avoid world-splitting in a
    # poorly-inferred caller
    InvalidA.callsfrts(1)
    InvalidA.callsfrts(Int8(1))
end

end # module InvalidD
