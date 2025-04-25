using SnoopCompileCore, SnoopCompile
using MethodAnalysis
using Pkg
using Test

module MethodLogs
Base.Experimental.@max_methods 2

include(joinpath(@__DIR__, "testmodules", "Invalidation", "InvalidA", "src", "pkgdef.jl"))

end

# Check the invalidation trees for `invs1`
function test_trees1(mod::Module, trees, mfint, mfstring, mfsigned, mfinteger, isedge::Bool)
    @test length(trees) == 5
    treefint    = SnoopCompile.firstmatch(trees, mfint)
    treefstring = SnoopCompile.firstmatch(trees, mfstring)
    treefsigned = SnoopCompile.firstmatch(trees, mfsigned)
    treeib = only(filter(trees) do tree
        ib = tree.cause
        isa(ib, Core.BindingPartition) || return false
        return isa(ib.restriction, DataType)
    end)
    treeconst = only(filter(trees) do tree
        ib = tree.cause
        isa(ib, Core.BindingPartition) || return false
        return !isa(ib.restriction, DataType) && ib.restriction.x === 1
    end)

    ## treefint
    # World-splitting in `mod.callsfrt[ar]`
    @test treefint.reason == :inserting
    root = SnoopCompile.firstmatch(treefint.backedges, Tuple{typeof(mod.f), Any}, Tuple{typeof(mod.f), Int})
    @test root.depth == 0
    edge = root.item
    @test edge.callee.def === mfinteger
    child = only(root.children)
    @test child.depth == 1
    @test child.item.def.def === only(methods(mod.callsfrta))
    node = only(child.children)
    @test node.depth == 2
    @test node.item.def.def === only(methods(mod.callscallsfrta)) && isempty(node.children)

    root = SnoopCompile.firstmatch(treefint.backedges, Tuple{typeof(mod.f), Real}, Tuple{typeof(mod.f), Int})
    @test root.depth == 0
    child = only(root.children)
    @test child.depth == 1
    @test child.item.def.def === only(methods(mod.callsfrtr))
    @test isempty(child.children)

    # Dispatch priority
    root = SnoopCompile.firstmatch(treefint.backedges, nothing, Tuple{typeof(mod.f), Signed})
    @test root.depth == 0
    edge = root.item
    @test edge.callee.def === mfinteger
    node = only(root.children)
    @test node.item.def.def === only(methods(mod.callsfrts))
    @test isempty(node.children)
    @test node.depth == 1

    root = SnoopCompile.firstmatch(treefint.backedges, nothing, Tuple{typeof(mod.f), Integer})
    @test root.depth == 0
    edge = root.item
    @test edge.callee.def === mfinteger
    node = SnoopCompile.firstmatch(root.children, only(methods(mod.callsfrta)))
    @test node.depth == 1
    @test isempty(node.children)
    node = SnoopCompile.firstmatch(root.children, only(methods(mod.callsfrtr)))
    @test isempty(node.children)
    @test node.depth == 1

    root = SnoopCompile.firstmatch(treefint.backedges, nothing, Tuple{typeof(mod.f), Int})
    @test root.depth == 0
    edge = root.item
    @test edge.callee.def === mfinteger
    @test length(root.children) == 2
    node = SnoopCompile.firstmatch(root.children, only(methods(mod.alsocallsf)))
    @test node.depth == 1
    @test isempty(node.children)
    node = SnoopCompile.firstmatch(root.children, only(methods(mod.callsf)))
    @test node.depth == 1
    child = only(node.children)
    @test child.depth == 2
    @test child.item.def.def == only(methods(mod.callscallsf))

    ## treefstring
    @test treefstring.reason == :inserting
    root = only(treefstring.backedges)
    edge = root.item
    @test edge.sig === Tuple{typeof(mod.f), String}
    @test edge.callee === nothing
    @test root.depth == 0
    child = only(root.children)
    @test child.depth == 1
    @test child.item.def.specTypes === Tuple{typeof(mod.callsf), String}
    node = only(child.children)
    @test node.depth == 2
    @test node.item.def.specTypes === Tuple{typeof(mod.callscallsf), String}
    @test isempty(node.children)

    ## treefsigned
    @test treefsigned.reason == :inserting
    root = only(treefsigned.backedges)
    edge = root.item
    if isedge
        error("checkme")
    end
    @test edge.callee.def === mfinteger && edge.callee.specTypes === Tuple{typeof(mod.f), Int}
    @test root.depth == 0
    node = only(root.children)
    @test node.depth == 1
    @test node.item.def.specTypes === Tuple{typeof(mod.invokesfs), Int}
    @test isempty(node.children)

    # treeib
    @test treeib.reason == :modifying
    root = only(treeib.backedges)
    edge = root.item
    @test edge.sig === nothing
    @test edge.callee.specTypes === Tuple{typeof(mod.makeib), Int}

    # treeconst
    @test treeconst.reason == :modifying
    root = only(treeconst.backedges)
    edge = root.item
    @test edge.sig === nothing
    @test edge.callee.specTypes === Tuple{typeof(mod.fib)}
end

function test_trees2(mod::Module, trees, mfint, mfint8, mfsigned, mfinteger, isedge::Bool)
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
    root = only(treefint8.backedges)
    @test root.depth == 0
    @test root.mi.def == mfsigned && root.mi.specTypes === Tuple{typeof(mod.f), Signed}
    @test length(root.children) == 2
    for node in root.children
        @test node.depth == 1
        @test node.mi.specTypes ∈ (Tuple{typeof(mod.callsfrts), Int}, Tuple{typeof(mod.callsfrts), Int8})
        @test isempty(node.children)
    end
end

mlogs = []

@testset "MethodLogs" begin
    empty!(mlogs)
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
    MethodLogs.fib()                               # binding

    invs1 = @snoop_invalidations begin
        MethodLogs.f(::Int) = 2
        MethodLogs.f(::String) = 3
        MethodLogs.f(::Signed) = 4
        @eval MethodLogs struct InvalidatedBinding
            x::Float64
        end
        @eval MethodLogs const gib = InvalidatedBinding(2.0)
    end
    # Grab the methods corresponding to invidual trees now, while they exist
    mfint, mfstring, mfsigned = which(f, (Int,)), which(f, (String,)), which(f, (Signed,))
    push!(mlogs, invs1)
    trees1 = invalidation_trees(invs1)
    push!(mlogs, trees1)

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
        Base.delete_method(mfint)
    end
    mfint8 = which(f, (Int8,))
    push!(mlogs, invs2)
    trees2 = invalidation_trees(invs2)
    push!(mlogs, trees2)

    push!(mlogs, mfint, mfstring, mfsigned, mfinteger, mfint8)

    ### invs1
    @test isempty(invs1.logedges)   # there were no precompiled packages
    # test_trees1(MethodLogs, trees1, mfint, mfstring, mfsigned, mfinteger, false)

    ### invs2
    @test isempty(invs2.logedges)   # there were no precompiled packages
    # test_trees2(MethodLogs, trees2, mfint, mfint8, mfsigned, mfinteger, false)
end
#=
elogs = []

@testset "Edge invalidations" begin
    empty!(elogs)
    cproj = Base.active_project()
    cd(joinpath(@__DIR__, "testmodules", "Invalidation")) do
        Pkg.activate(pwd())
        Pkg.develop(path="./InvalidA")
        Pkg.develop(path="./InvalidB")
        Pkg.develop(path="./InvalidC")

        InvalidC, InvalidA = @eval begin
            using InvalidC        # this is InvalidA + new methods
            InvalidC, InvalidC.InvalidA
        end
        invs1 = @snoop_invalidations begin
            @eval InvalidA struct InvalidatedBinding
                x::Float64
            end
            @eval InvalidA const gib = makeib(2.0)
            @eval using InvalidB  # this is InvalidA + precompilation
        end
        f = InvalidA.f
        mfint, mfstring, mfsigned, mfinteger = which(f, (Int,)), which(f, (String,)), which(f, (Signed,)), which(f, (Integer,))
        @show mfint mfinteger

        @test isempty(invs1.logmeths)
        push!(elogs, invs1)
        # trees = invalidation_trees(invs1; consolidate=false)
        # push!(elogs, trees)
        # display(trees)
        # test_trees1(InvalidA, trees, mfint, mfstring, mfsigned, mfinteger, true)

        invs2 = @snoop_invalidations begin
            @eval using InvalidE    # add methods
            Base.delete_method(mfint)
            @eval using InvalidD    # add precompiles that depend on InvalidA + InvalidB + InvalidC
        end

        @test isempty(invs2.logmeths)
        push!(elogs, invs2)
        # trees = invalidation_trees(invs2; consolidate=false)
        # push!(elogs, trees)
        # display(trees)
        # test_trees2(InvalidA, trees, mfint, mfstring, mfsigned, mfinteger, true)
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
=#