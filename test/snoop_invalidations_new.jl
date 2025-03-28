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
callscallsfrta(x) = callsfrta(x)
# invoked callers
invokesfr(x) = invoke(f, Tuple{Real}, x)
invokesfs(x) = invoke(f, Tuple{Signed}, x)

end

@testset "MethodLogs" begin
    f = MethodLogs.f
    mfinteger = only(methods(f))
    precompile(MethodLogs.callscallsf, (String,))  # unresolved callee (would throw an error if we called it)
    MethodLogs.callscallsf(1)                      # resolved callee
    MethodLogs.alsocallsf(1)                       # resolved callee (different branch)
    MethodLogs.invokesfs(1)                        # invoked callee
    precompile(MethodLogs.invokesfr, (Int,))       # invoked callee (would error if called)
    MethodLogs.callscallsfrta(1)                        # runtime-dispatched callee
    MethodLogs.callsfrtr(1)
    MethodLogs.callsfrts(1)

    invs1 = @snoop_invalidations begin
        MethodLogs.f(::Int) = 2
        MethodLogs.f(::String) = 3
        MethodLogs.f(::Signed) = 4
    end
    # Grab the methods corresponding to invidual trees now, while they exist
    mfint, mfstring, mfsigned = which(f, (Int,)), which(f, (String,)), which(f, (Signed,))

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
        Base.delete_method(which(f, (Int,)))
    end
    mfint8 = which(f, (Int8,))

    ### invs1
    @test isempty(invs1.logedges)   # there were no precompiled packages
    trees = invalidation_trees(invs1)
    @test length(trees) == 3
    treefint    = SnoopCompile.firstmatch(trees, mfint)
    treefstring = SnoopCompile.firstmatch(trees, mfstring)
    treefsigned = SnoopCompile.firstmatch(trees, mfsigned)

    ## treefint
    # World-splitting in `MethodLogs.callsfrt[ar]`
    @test treefint.reason == :inserting
    @test length(treefint.mt_backedges) == 2
    sig, root = SnoopCompile.firstmatch(treefint.mt_backedges, Tuple{typeof(f), Any})
    @test root.depth == 0
    @test root.mi.def === only(methods(MethodLogs.callsfrta))
    node = only(root.children)
    @test node.depth == 1
    @test node.mi.def === only(methods(MethodLogs.callscallsfrta)) && isempty(node.children)

    sig, root = SnoopCompile.firstmatch(treefint.mt_backedges, Tuple{typeof(f), Real})
    @test root.depth == 0
    @test root.mi.def === only(methods(MethodLogs.callsfrtr))
    @test isempty(root.children)

    # Dispatch priority
    @test length(treefint.backedges) == 3
    root = treefint.backedges[1]
    @test root.depth == 0
    @test root.mi.def === mfinteger && root.mi.specTypes == Tuple{typeof(f), Signed}
    node = only(root.children)
    @test node.mi.def === only(methods(MethodLogs.callsfrts)) # Because Signed <: Integer, it's in `backedges` not `mt_backedges`
    @test isempty(node.children)
    @test node.depth == 1
    
    root = treefint.backedges[2]
    @test root.depth == 0
    @test root.mi.def === mfinteger && root.mi.specTypes == Tuple{typeof(f), Integer}
    node = SnoopCompile.firstmatch(root.children, only(methods(MethodLogs.callsfrta)))
    @test node.depth == 1
    @test isempty(node.children)
    node = SnoopCompile.firstmatch(root.children, only(methods(MethodLogs.callsfrtr)))
    @test isempty(node.children)
    @test node.depth == 1

    root = treefint.backedges[3]
    @test root.depth == 0
    @test root.mi.def === mfinteger && root.mi.specTypes == Tuple{typeof(f), Int}
    @test SnoopCompile.countchildren(root) == 3
    @test length(root.children) == 2
    node = SnoopCompile.firstmatch(root.children, only(methods(MethodLogs.alsocallsf)))
    @test node.depth == 1
    @test isempty(node.children)
    node = SnoopCompile.firstmatch(root.children, only(methods(MethodLogs.callsf)))
    @test node.depth == 1
    child = only(node.children)
    @test child.depth == 2
    @test child.mi.def == only(methods(MethodLogs.callscallsf))
 
    ## treefstring
    @test treefstring.reason == :inserting
    @test isempty(treefstring.backedges)
    sig, root = only(treefstring.mt_backedges)
    @test sig === Tuple{typeof(f), String}
    @test root.depth == 0
    @test root.mi.specTypes === Tuple{typeof(MethodLogs.callsf), String}
    node = only(root.children)
    @test node.depth == 1
    @test node.mi.specTypes === Tuple{typeof(MethodLogs.callscallsf), String}
    @test isempty(node.children)

    ## treefsigned
    @test treefsigned.reason == :inserting
    @test isempty(treefsigned.mt_backedges)
    @test length(treefsigned.backedges) == 3
    root = treefsigned.backedges[end]
    @test root.depth == 0
    @test root.mi.def === mfinteger && root.mi.specTypes === Tuple{typeof(f), Int}
    node = only(root.children)
    @test node.depth == 1
    @test node.mi.specTypes === Tuple{typeof(MethodLogs.invokesfs), Int}
    @test isempty(node.children)

    for i = 1:2
        local root = treefsigned.backedges[i]
        @test isempty(root.children)
        @test root.mi.def === mfinteger && root.mi.specTypes ∈ (Tuple{typeof(f), Integer}, Tuple{typeof(f), Signed})
    end
    @test treefsigned.backedges[1].mi.specTypes !== treefsigned.backedges[2].mi.specTypes

    ### invs2
    @test isempty(invs2.logedges)   # there were no precompiled packages
    trees = invalidation_trees(invs2)
    @test length(trees) == 2
    treefint  = SnoopCompile.firstmatch(trees, mfint)
    treefint8 = SnoopCompile.firstmatch(trees, mfint8)

    ## treefint
    @test treefint.reason == :deleting
    @test isempty(treefint.mt_backedges)
    root = only(treefint.backedges)
    @test root.depth == 0
    @test length(root.children) == 4
    node = root.children[end]
    @test node.depth == 1
    @test node.mi.def === only(methods(MethodLogs.callsf)) && node.mi.specTypes === Tuple{typeof(MethodLogs.callsf), Int}
    node = only(node.children)
    @test node.mi.specTypes === Tuple{typeof(MethodLogs.callscallsf), Int}
    node = SnoopCompile.firstmatch(root.children, only(methods(MethodLogs.alsocallsf)))
    @test node.depth == 1
    @test isempty(node.children)
    node = SnoopCompile.firstmatch(root.children, Tuple{typeof(MethodLogs.callsfrts), Int})
    @test node.depth == 1
    @test isempty(node.children)
    node = SnoopCompile.firstmatch(root.children, Tuple{typeof(MethodLogs.callsfrts), Int8})
    @test node.depth == 1
    @test isempty(node.children)

    ## treefint8
    @test treefint8.reason == :inserting
    @test isempty(treefint8.mt_backedges)
    root = treefint8.backedges[end]
    @test root.depth == 0
    @test root.mi.def == mfsigned && root.mi.specTypes === Tuple{typeof(f), Signed}
    @test length(root.children) == 2
    for node in root.children
        @test node.depth == 1
        @test node.mi.specTypes ∈ (Tuple{typeof(MethodLogs.callsfrts), Int}, Tuple{typeof(MethodLogs.callsfrts), Int8})
        @test isempty(node.children)
    end

    root = SnoopCompile.firstmatch(treefint8.backedges[1:2], Tuple{typeof(f), Signed})  # from invokesfs
    @test root.mi.def === mfinteger
    @test isempty(root.children)
    root = SnoopCompile.firstmatch(treefint8.backedges[1:2], Tuple{typeof(f), Integer})  # from callsfrts
    @test root.mi.def === mfinteger
    @test isempty(root.children)
end
