using SnoopCompileCore, SnoopCompile
using Test

module MethodLogs
Base.Experimental.@max_methods 2

f(::Integer) = 1
callsf(x) = f(x)
callscallsf(x) = callsf(x)
alsocallsf(x) = f(x+1)
# runtime-dispatched callers
callsfrta(x) = f(Base.inferencebarrier(x))
callsfrti(x) = f(Base.inferencebarrier(x)::Real)
callsfrts(x) = f(Base.inferencebarrier(x)::Signed)
# invoked callers
invokesfr(x) = invoke(f, Tuple{Real}, x)
invokesfs(x) = invoke(f, Tuple{Signed}, x)

end

#@testset "MethodLogs" begin
    # precompile(MethodLogs.callscallsf, (String,))  # unresolved callee (would throw an error if we called it)
    # MethodLogs.callscallsf(1)                      # resolved callee
    # MethodLogs.alsocallsf(1)                       # resolved callee (different branch)
    # MethodLogs.invokesfs(1)                        # invoked callee
    # MethodLogs.invokesfr(1)                        # invoked callee
    MethodLogs.callsfrta(1)                          # runtime-dispatched callee
    MethodLogs.callsfrti(1)
    MethodLogs.callsfrts(1)

    invs1 = @snoop_invalidations begin
        MethodLogs.f(::Int) = 2
        # MethodLogs.f(::String) = 3
        # MethodLogs.f(::Signed) = 4
    end

    error("stop")

    # Recompile
    MethodLogs.callscallsf(1)
    MethodLogs.alsocallsf(1)
    MethodLogs.invokesf(1)
    # We now have enough methods of `MethodLogs.f` to avoid world-splitting in a
    # poorly-inferred caller
    MethodLogs.callsfrt(1)
    MethodLogs.callsfrt(Int8(1))

    invs2 = @snoop_invalidations begin
        MethodLogs.f(::Int8) = 5
        Base.delete_method(which(MethodLogs.f, (Int,)))
    end

    # Now the tests
    @test isempty(invs1.logedges)   # there were no precompiled packages
    trees = invalidation_trees(invs1)
    invms = [tree.method for tree in trees]
    mfstring, mfsigned = which(MethodLogs.f, (String,)), which(MethodLogs.f, (Signed,))
    treefstring = trees[findfirst(m -> m === mfstring, invms)]
    treefsigned = trees[findfirst(m -> m === mfsigned, invms)]
    # the method for Int got deleted so we have to find it more laboriously
    treefint = trees[findfirst(m -> m.deleted_world < typemax(UInt), invms)]
    # World-splitting in `MethodLogs.callsfrt`
    sig, root = only(treefint.mt_backedges)
    @test sig === Tuple{typeof(Main.MethodLogs.f), Any}
    @test root.mi.def === only(methods(MethodLogs.callsfrt))
    @test isempty(root.children)
#end
