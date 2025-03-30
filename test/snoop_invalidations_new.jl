using SnoopCompileCore, SnoopCompile
using Pkg
using Test

module MethodLogs
Base.Experimental.@max_methods 2

include(joinpath(@__DIR__, "testmodules", "Invalidation", "InvalidA", "src", "pkgdef.jl"))

end

# Check the invalidation trees for `invs1`
function test_trees1(mod::Module, trees, mfint, mfstring, mfsigned, mfinteger)
    @test length(trees) == 3
    treefint    = SnoopCompile.firstmatch(trees, mfint)
    treefstring = SnoopCompile.firstmatch(trees, mfstring)
    treefsigned = SnoopCompile.firstmatch(trees, mfsigned)

    ## treefint
    # World-splitting in `mod.callsfrt[ar]`
    @test treefint.reason == :inserting
    @test length(treefint.mt_backedges) == 2
    sig, root = SnoopCompile.firstmatch(treefint.mt_backedges, Tuple{typeof(mod.f), Any})
    @test root.depth == 0
    @test root.mi.def === only(methods(mod.callsfrta))
    node = only(root.children)
    @test node.depth == 1
    @test node.mi.def === only(methods(mod.callscallsfrta)) && isempty(node.children)

    sig, root = SnoopCompile.firstmatch(treefint.mt_backedges, Tuple{typeof(mod.f), Real})
    @test root.depth == 0
    @test root.mi.def === only(methods(mod.callsfrtr))
    @test isempty(root.children)

    # Dispatch priority
    @test length(treefint.backedges) == 3
    root = treefint.backedges[1]
    @test root.depth == 0
    @test root.mi.def === mfinteger && root.mi.specTypes == Tuple{typeof(mod.f), Signed}
    node = only(root.children)
    @test node.mi.def === only(methods(mod.callsfrts)) # Because Signed <: Integer, it's in `backedges` not `mt_backedges`
    @test isempty(node.children)
    @test node.depth == 1

    root = treefint.backedges[2]
    @test root.depth == 0
    @test root.mi.def === mfinteger && root.mi.specTypes == Tuple{typeof(mod.f), Integer}
    node = SnoopCompile.firstmatch(root.children, only(methods(mod.callsfrta)))
    @test node.depth == 1
    @test isempty(node.children)
    node = SnoopCompile.firstmatch(root.children, only(methods(mod.callsfrtr)))
    @test isempty(node.children)
    @test node.depth == 1

    root = treefint.backedges[3]
    @test root.depth == 0
    @test root.mi.def === mfinteger && root.mi.specTypes == Tuple{typeof(mod.f), Int}
    @test SnoopCompile.countchildren(root) == 3
    @test length(root.children) == 2
    node = SnoopCompile.firstmatch(root.children, only(methods(mod.alsocallsf)))
    @test node.depth == 1
    @test isempty(node.children)
    node = SnoopCompile.firstmatch(root.children, only(methods(mod.callsf)))
    @test node.depth == 1
    child = only(node.children)
    @test child.depth == 2
    @test child.mi.def == only(methods(mod.callscallsf))

    ## treefstring
    @test treefstring.reason == :inserting
    @test isempty(treefstring.backedges)
    sig, root = only(treefstring.mt_backedges)
    @test sig === Tuple{typeof(mod.f), String}
    @test root.depth == 0
    @test root.mi.specTypes === Tuple{typeof(mod.callsf), String}
    node = only(root.children)
    @test node.depth == 1
    @test node.mi.specTypes === Tuple{typeof(mod.callscallsf), String}
    @test isempty(node.children)

    ## treefsigned
    @test treefsigned.reason == :inserting
    @test isempty(treefsigned.mt_backedges)
    @test length(treefsigned.backedges) == 3
    root = treefsigned.backedges[end]
    @test root.depth == 0
    @test root.mi.def === mfinteger && root.mi.specTypes === Tuple{typeof(mod.f), Int}
    node = only(root.children)
    @test node.depth == 1
    @test node.mi.specTypes === Tuple{typeof(mod.invokesfs), Int}
    @test isempty(node.children)

    for i = 1:2
        local root = treefsigned.backedges[i]
        @test isempty(root.children)
        @test root.mi.def === mfinteger && root.mi.specTypes ∈ (Tuple{typeof(mod.f), Integer}, Tuple{typeof(mod.f), Signed})
    end
    @test treefsigned.backedges[1].mi.specTypes !== treefsigned.backedges[2].mi.specTypes
end

function test_trees2(mod::Module, trees, mfint, mfint8, mfsigned, mfinteger)
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
    @test node.mi.def === only(methods(mod.callsf)) && node.mi.specTypes === Tuple{typeof(mod.callsf), Int}
    node = only(node.children)
    @test node.mi.specTypes === Tuple{typeof(mod.callscallsf), Int}
    node = SnoopCompile.firstmatch(root.children, only(methods(mod.alsocallsf)))
    @test node.depth == 1
    @test isempty(node.children)
    node = SnoopCompile.firstmatch(root.children, Tuple{typeof(mod.callsfrts), Int})
    @test node.depth == 1
    @test isempty(node.children)
    node = SnoopCompile.firstmatch(root.children, Tuple{typeof(mod.callsfrts), Int8})
    @test node.depth == 1
    @test isempty(node.children)

    ## treefint8
    @test treefint8.reason == :inserting
    @test isempty(treefint8.mt_backedges)
    root = treefint8.backedges[end]
    @test root.depth == 0
    @test root.mi.def == mfsigned && root.mi.specTypes === Tuple{typeof(mod.f), Signed}
    @test length(root.children) == 2
    for node in root.children
        @test node.depth == 1
        @test node.mi.specTypes ∈ (Tuple{typeof(mod.callsfrts), Int}, Tuple{typeof(mod.callsfrts), Int8})
        @test isempty(node.children)
    end

    root = SnoopCompile.firstmatch(treefint8.backedges[1:2], Tuple{typeof(mod.f), Signed})  # from invokesfs
    @test root.mi.def === mfinteger
    @test isempty(root.children)
    root = SnoopCompile.firstmatch(treefint8.backedges[1:2], Tuple{typeof(mod.f), Integer})  # from callsfrts
    @test root.mi.def === mfinteger
    @test isempty(root.children)
end

@testset "MethodLogs" begin
    f = MethodLogs.f
    mfinteger = only(methods(f))
    precompile(MethodLogs.callscallsf, (String,))  # unresolved callee (would throw an error if we called it)
    MethodLogs.callscallsf(1)                      # resolved callee
    MethodLogs.alsocallsf(1)                       # resolved callee (different branch)
    MethodLogs.invokesfs(1)                        # invoked callee
    precompile(MethodLogs.invokesfr, (Int,))       # invoked callee (would error if called)
    MethodLogs.callscallsfrta(1)                   # runtime-dispatched callee
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
    test_trees1(MethodLogs, trees, mfint, mfstring, mfsigned, mfinteger)

    ### invs2
    @test isempty(invs2.logedges)   # there were no precompiled packages
    trees = invalidation_trees(invs2)
    test_trees2(MethodLogs, trees, mfint, mfint8, mfsigned, mfinteger)
end

@testset "Edge invalidations" begin
    cproj = Base.active_project()
    cd(joinpath(@__DIR__, "testmodules", "Invalidation")) do
        Pkg.activate(pwd())
        Pkg.develop(path="./InvalidA")
        Pkg.develop(path="./InvalidB")
        Pkg.develop(path="./InvalidC")

        mod = @eval begin
            using InvalidC      # this is InvalidA + new methods
            InvalidC
        end
        invs1 = @snoop_invalidations begin
            @eval using InvalidB  # this is InvalidA + precompilation
        end
        f = mod.InvalidA.f
        mfint, mfstring, mfsigned, mfinteger = which(f, (Int,)), which(f, (String,)), which(f, (Signed,)), which(f, (Integer,))

        @test isempty(invs1.logmeths)
        trees = invalidation_trees(invs1)
        display(trees)
        test_trees1(mod.InvalidA, trees, mfint, mfstring, mfsigned, mfinteger)

    end
    Base.activate(cproj) # Reactivate the original project
end

# # @testset "Edge invalidations" begin
#     cproj = Base.active_project()
#     cd(joinpath(@__DIR__, "testmodules", "Invalidation"))
#     Pkg.activate(pwd())
#     Pkg.develop(path="./PkgC")
#     Pkg.develop(path="./PkgD")
#     Pkg.precompile()
#     ref1, ref2 = Ref{Int}(0), Ref{Any}() # to check that `const` changes really happened and were measured in the right world age
#     invalidations = @snoop_invalidations begin
#         @eval using PkgC
#         # PkgC is a dependency of PkgD. Now that we've loaded PkgC into this session, let's make some changes to its contents.
#         @eval PkgC begin
#             const someconst = 10
#             struct MyType
#                 x::Int8
#             end
#         end
#         @eval begin
#             PkgC.nbits(::UInt8) = 8
#             PkgC.nbits(::UInt16) = 16
#             Base.delete_method(which(PkgC.nbits, (Integer,)))
#         end
#         # The changes should trigger invalidations during loading of PkgD
#         @eval using PkgD
#         # In case binding-change invalidations require execution to propagate
#         ref1[] = PkgD.uses_someconst(1)
#         ref2[] = PkgD.calls_mytype(1)
#     end
#     Pkg.activate(cproj)
#     @test isempty(invalidations.logmeths)
#     trees = invalidation_trees(invalidations; consolidate=false)
#     # tree = only(invalidation_trees(invalidations))
#     # @test tree.reason == :inserting
#     # @test tree.method.file == Symbol(@__FILE__)
#     # @test isempty(tree.backedges)
#     # sig, root = only(tree.mt_backedges)
#     # @test sig.parameters[1] === typeof(PkgC.nbits)
#     # @test sig.parameters[2] === Integer
#     # @test root.mi == first(SnoopCompile.specializations(only(methods(PkgD.call_nbits))))

# # end
