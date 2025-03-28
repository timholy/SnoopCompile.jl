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
callsfrtr(x) = f(Base.inferencebarrier(x)::Real)
callsfrts(x) = f(Base.inferencebarrier(x)::Signed)
# invoked callers
invokesfr(x) = invoke(f, Tuple{Real}, x)
invokesfs(x) = invoke(f, Tuple{Signed}, x)

end

function validate_mt_backedge(root, i=nothing)
    # There are two implementations that make sense:
    # 1. keep the depth-0 root and add the (redundant?) depth-1 node
    # 2. replace the root with the depth-1 node
    # Write the tests so that either choice passes
    if isempty(root.children)
        @test root.depth == 1
        return root
    end
    node = i === nothing ? only(root.children) : root.children[i]
    @test root.depth == 0
    @test node.depth == 1
    @test root.mi === node.mi
    return node
end

#@testset "MethodLogs" begin
    precompile(MethodLogs.callscallsf, (String,))  # unresolved callee (would throw an error if we called it)
    MethodLogs.callscallsf(1)                      # resolved callee
    MethodLogs.alsocallsf(1)                       # resolved callee (different branch)
    MethodLogs.invokesfs(1)                        # invoked callee
    precompile(MethodLogs.invokesfr, (Int,))       # invoked callee (would error if called)
    MethodLogs.callsfrta(1)                        # runtime-dispatched callee
    MethodLogs.callsfrtr(1)
    MethodLogs.callsfrts(1)

    invs1 = @snoop_invalidations begin
        MethodLogs.f(::Int) = 2
        MethodLogs.f(::String) = 3
        MethodLogs.f(::Signed) = 4
    end
    # Grab the methods corresponding to invidual trees now, while they exist
    mfint, mfstring, mfsigned = which(MethodLogs.f, (Int,)), which(MethodLogs.f, (String,)), which(MethodLogs.f, (Signed,))

    # Recompile
    MethodLogs.callscallsf(1)
    MethodLogs.alsocallsf(1)
    MethodLogs.invokesfs(1)
    # We now have enough methods of `MethodLogs.f` to avoid world-splitting in a
    # poorly-inferred caller
    MethodLogs.callsfrts(1)
    MethodLogs.callsfrts(Int8(1))

    invs2 = @snoop_invalidations begin
        MethodLogs.f(::Int8) = 5
        Base.delete_method(which(MethodLogs.f, (Int,)))
    end

    # Now the tests
    @test isempty(invs1.logedges)   # there were no precompiled packages
    trees = invalidation_trees(invs1)
    treefint    = firsttree(trees, mfint)
    treefstring = firsttree(trees, mfstring)
    treefsigned = firsttree(trees, mfsigned)
    # World-splitting in `MethodLogs.callsfrt`
    i = findfirst(((sig, root),) -> sig === Tuple{typeof(Main.MethodLogs.f), Any}, treefint.mt_backedges)
    sig, root = treefint.mt_backedges[i]
    @test root.mi.def === only(methods(MethodLogs.callsfrta))
    @test validate_mt_backedge(root).mi.def === only(methods(MethodLogs.callsfrta))
    i = findfirst(((sig, root),) -> sig === Tuple{typeof(Main.MethodLogs.f), Real}, treefint.mt_backedges)
    sig, root = treefint.mt_backedges[i]
    @test root.mi.def === only(methods(MethodLogs.callsfrtr))
    @test validate_mt_backedge(root).mi.def === only(methods(MethodLogs.callsfrtr))
#end
