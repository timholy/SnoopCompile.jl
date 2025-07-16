f(::Integer) = 1
callsf(x) = f(x)
callscallsf(x) = callsf(x)
alsocallsf(x) = f(x+1)
# runtime-dispatched callers
callsfrta(x) = f(Base.inferencebarrier(x))
callsfrtr(x) = f(Base.inferencebarrier(x)::Real)
callsfrts(x) = f(Base.inferencebarrier(x)::Signed)
callscallsfrta(x) = callsfrta(x)
# invoked callers
invokesfr(x) = invoke(f, Tuple{Real}, x)
invokesfs(x) = invoke(f, Tuple{Signed}, x)
