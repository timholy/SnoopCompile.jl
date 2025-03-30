module InvalidB

using InvalidA
using PrecompileTools

# Precompilation
precompile(InvalidA.callscallsf, (String,))  # unresolved callee (would throw an error if we called it)
precompile(InvalidA.invokesfr, (Int,))       # invoked callee (would error if called)
@compile_workload begin
    Base.Experimental.@force_compile
    InvalidA.callscallsf(1)                      # resolved callee
    InvalidA.alsocallsf(1)                       # resolved callee (different branch)
    InvalidA.invokesfs(1)                        # invoked callee
    InvalidA.callscallsfrta(1)                   # runtime-dispatched callee
    InvalidA.callsfrtr(1)
    InvalidA.callsfrts(1)
end

end
