using SnoopCompile, InteractiveUtils, MethodAnalysis, Test

module SnooprTests
f(x::Int)  = 1
f(x::Bool) = 2
applyf(container) = f(container[1])
callapplyf(container) = applyf(container)

# "multi-caller". Mimics invalidations triggered by defining ==(::SomeType, ::Any)
mc(x, y) = false
mc(x::Int, y::Int) = x === y
mc(x::Symbol, y::Symbol) = x === y
function mcc(container, y)
    x = container[1]
    return mc(x, y)
end
function mcc(container, y, extra)
    x = container[1]
    return mc(x, y) + extra
end
mccc1(container, y) = mcc(container, y)
mccc2(container, y) = mcc(container, y, 10)

end

@testset "@snoopr" begin
    c = Any[1]
    @test SnooprTests.callapplyf(c) == 1
    mi1 = instance(SnooprTests.applyf, (Vector{Any},))
    mi2 = instance(SnooprTests.callapplyf, (Vector{Any},))

    invs = @snoopr SnooprTests.f(::AbstractFloat) = 3
    @test !isempty(invs)
    trees = invalidation_trees(invs)

    tree = only(trees)
    m = which(SnooprTests.f, (AbstractFloat,))
    @test tree.method == m
    @test tree.reason === :insert
    sig, node = only(tree.mt_backedges)
    @test sig === Tuple{typeof(SnooprTests.f), Any}
    @test node.mi == mi1
    @test SnoopCompile.getroot(node) === node
    @test node.depth == 0
    child = only(node.children)
    @test child.mi == mi2
    @test SnoopCompile.getroot(child) === node
    @test child.depth == 1
    @test isempty(child.children)
    @test isempty(tree.backedges)

    io = IOBuffer()
    print(io, tree)
    str = String(take!(io))
    @test startswith(str, "insert f(::AbstractFloat)")
    @test occursin("mt_backedges: 1: signature", str)
    @test occursin("triggered MethodInstance for applyf(::Array{Any,1}) (1 children) more specific", str)

    cf = Any[1.0f0]
    @test SnooprTests.callapplyf(cf) == 3
    mi3 = instance(SnooprTests.f, (AbstractFloat,))
    invs = @snoopr SnooprTests.f(::Float32) = 4
    @test !isempty(invs)
    trees = invalidation_trees(invs)

    tree = only(trees)
    m = which(SnooprTests.f, (Float32,))
    # These next are identical to the above
    @test tree.method == m
    @test tree.reason === :insert
    sig, node = only(tree.mt_backedges)
    @test sig === Tuple{typeof(SnooprTests.f), Any}
    @test node.mi == mi1
    @test SnoopCompile.getroot(node) === node
    @test node.depth == 0
    child = only(node.children)
    @test child.mi == mi2
    @test SnoopCompile.getroot(child) === node
    @test child.depth == 1
    @test isempty(child.children)
    # But we add backedges
    node = only(tree.backedges)
    @test node.mi == mi3
    @test SnoopCompile.getroot(node) === node
    @test node.depth == 0
    child = only(node.children)
    @test child.mi == mi1
    @test SnoopCompile.getroot(child) === node
    @test child.depth == 1

    @test  any(nd->nd.mi == mi1, node)
    @test !any(nd->nd.mi == mi3, child)

    print(io, tree)
    str = String(take!(io))
    @test startswith(str, "insert f(::Float32)")
    @test occursin("mt_backedges: 1: signature", str)
    @test occursin("triggered MethodInstance for applyf(::Array{Any,1}) (1 children) more specific", str)
    @test occursin("backedges: 1: superseding f(::AbstractFloat)", str)
    @test occursin("with MethodInstance for f(::AbstractFloat) (1 children) more specific", str)

    show(io, node; minchildren=0)
    str = String(take!(io))
    lines = split(chomp(str), '\n')
    @test length(lines) == 2
    @test lines[1] == "MethodInstance for f(::AbstractFloat) (1 children)"
    @test lines[2] == " MethodInstance for applyf(::Array{Any,1}) (0 children)"
    show(io, node; minchildren=1)
    str = String(take!(io))
    lines = split(chomp(str), '\n')
    @test length(lines) == 2
    @test lines[1] == "MethodInstance for f(::AbstractFloat) (1 children)"
    @test lines[2] == "⋮"

    ftrees = filtermod(SnooprTests, trees)
    ftree = only(ftrees)
    @test ftree.mt_backedges == tree.mt_backedges
    @test isempty(ftree.backedges)
    ftrees = filtermod(@__MODULE__, trees)
    ftree = only(ftrees)
    @test ftree.backedges == tree.backedges
    @test isempty(ftree.mt_backedges)

    cai = Any[1]
    cas = Any[:sym]
    @test SnooprTests.mccc1(cai, 1)
    @test !SnooprTests.mccc1(cai, 2)
    @test !SnooprTests.mccc1(cas, 1)
    @test SnooprTests.mccc2(cai, 1) == 11
    @test SnooprTests.mccc2(cai, 2) == 10
    @test SnooprTests.mccc2(cas, 1) == 10
    trees = invalidation_trees(@snoopr SnooprTests.mc(x::AbstractFloat, y::Int) = x == y)
    node = only(trees).backedges[1]
    @test length(node.children) == 2
    m = which(SnooprTests.mccc1, (Any, Any))
    ft = findcaller(m, trees)
    fnode = only(ft.backedges)
    while !isempty(fnode.children)
        fnode = only(fnode.children)
    end
    @test fnode.mi.def === m
end
