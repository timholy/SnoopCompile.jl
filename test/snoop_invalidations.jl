using SnoopCompile, InteractiveUtils, MethodAnalysis, Pkg, Test
import PrettyTables # so that the report_invalidations.jl file is loaded


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

struct MyInt <: Integer
    x::Int
end

end

# For recursive filtermod
module Inner
    op(a, b) = a + b
end
module Outer
    using ..Inner
    function runop(list)
        acc = 0
        for item in list
            acc = Inner.op(acc, item)
        end
        return acc
    end
end


@testset "@snoop_invalidations" begin
    prefix = "$(@__MODULE__).SnooprTests."

    c = Any[1]
    @test SnooprTests.callapplyf(c) == 1
    mi1 = methodinstance(SnooprTests.applyf, (Vector{Any},))
    mi2 = methodinstance(SnooprTests.callapplyf, (Vector{Any},))

    @test length(uinvalidated([mi1])) == 1  # issue #327
    @test length(uinvalidated([mi1, "verify_methods", mi2])) == 1
    @test length(uinvalidated([mi1, "invalidate_mt_cache"])) == 0

    invs = @snoop_invalidations SnooprTests.f(::AbstractFloat) = 3
    @test !isempty(invs)
    umis = uinvalidated(invs)
    @test !isempty(umis)
    trees = invalidation_trees(invs)

    methinvs = only(trees)
    m = which(SnooprTests.f, (AbstractFloat,))
    @test methinvs.method == m
    @test methinvs.reason === :inserting
    sig, root = only(methinvs.mt_backedges)
    @test sig === Tuple{typeof(SnooprTests.f), Any}
    @test root.mi == mi1
    @test SnoopCompile.getroot(root) === root
    @test root.depth == 0
    child = only(root.children)
    @test child.mi == mi2
    @test SnoopCompile.getroot(child) === root
    @test child.depth == 1
    @test isempty(child.children)
    @test isempty(methinvs.backedges)

    io = IOBuffer()
    print(io, methinvs)
    str = String(take!(io))
    @test startswith(str, "inserting f(::AbstractFloat)")
    @test occursin("mt_backedges: 1: signature", str)
    @test occursin("triggered MethodInstance for $(prefix)applyf(::$(Vector{Any})) (1 children)", str)

    cf = Any[1.0f0]
    @test SnooprTests.callapplyf(cf) == 3
    mi1 = methodinstance(SnooprTests.applyf, (Vector{Any},))
    mi2 = methodinstance(SnooprTests.callapplyf, (Vector{Any},))
    @test mi1.backedges == [mi2]
    mi3 = methodinstance(SnooprTests.f, (AbstractFloat,))
    invs = @snoop_invalidations SnooprTests.f(::Float32) = 4
    @test !isempty(invs)
    trees = invalidation_trees(invs)

    methinvs = only(trees)
    m = which(SnooprTests.f, (Float32,))
    # These next are identical to the above
    @test methinvs.method == m
    @test methinvs.reason === :inserting
    have_backedges = !isempty(methinvs.backedges)
    if have_backedges
        root = only(methinvs.backedges)
        @test root.mi == mi3
        @test SnoopCompile.getroot(root) === root
        @test root.depth == 0
        child = only(root.children)
        @test child.mi == mi1
        @test SnoopCompile.getroot(child) === root
        @test child.depth == 1
    end
    if isempty(methinvs.backedges) || isempty(child.children)
        # the mt_backedges got invalidated first
        sig, root = only(methinvs.mt_backedges)
        @test sig === Tuple{typeof(Main.SnooprTests.f), Any}
        @test root.mi == mi1
        cchild = only(root.children)
        targetdepth = 1
    else
        cchild = only(child.children)
        targetdepth = 2
    end
    @test cchild.mi == mi2
    @test SnoopCompile.getroot(cchild) === root
    @test cchild.depth == targetdepth
    @test isempty(cchild.children)

    @test  any(nd->nd.mi == mi1, root)
    @test !any(nd->nd.mi == mi3, child)

    print(io, methinvs)
    str = String(take!(io))
    @test startswith(str, "inserting f(::Float32)")
    if !isempty(methinvs.backedges)
        @test occursin("backedges: 1: superseding f(::AbstractFloat)", str)
        @test occursin("with MethodInstance for $(prefix)f(::AbstractFloat) ($targetdepth children)", str)
    else
        @test occursin("signature Tuple{typeof($(prefix)f), Any} triggered", str)
        @test occursin("for $(prefix)applyf(::Vector{Any}) ($targetdepth children)", str)
    end

    show(io, root; minchildren=1)
    str = String(take!(io))
    lines = split(chomp(str), '\n')
    @test length(lines) == 1+targetdepth
    if targetdepth == 2
        @test lines[1] == "MethodInstance for $(prefix)f(::AbstractFloat) (2 children)"
        @test lines[2] == " MethodInstance for $(prefix)applyf(::$(Vector{Any})) (1 children)"
    else
        @test lines[1] == "MethodInstance for $(prefix)applyf(::$(Vector{Any})) (1 children)"
    end
    show(io, root; minchildren=2)
    str = String(take!(io))
    lines = split(chomp(str), '\n')
    @test length(lines) == 2
    @test lines[1] == (targetdepth == 2 ? "MethodInstance for $(prefix)f(::AbstractFloat) (2 children)" :
                                          "MethodInstance for $(prefix)applyf(::$(Vector{Any})) (1 children)")
    @test lines[2] == "⋮"

    if have_backedges
        ftrees = filtermod(@__MODULE__, trees)
        ftree = only(ftrees)
        @test ftree.backedges == methinvs.backedges
        @test isempty(ftree.mt_backedges)
    else
        ftrees = filtermod(SnooprTests, trees)
        @test ftrees == trees
    end

    cai = Any[1]
    cas = Any[:sym]
    @test SnooprTests.mccc1(cai, 1)
    @test !SnooprTests.mccc1(cai, 2)
    @test !SnooprTests.mccc1(cas, 1)
    @test SnooprTests.mccc2(cai, 1) == 11
    @test SnooprTests.mccc2(cai, 2) == 10
    @test SnooprTests.mccc2(cas, 1) == 10
    trees = invalidation_trees(@snoop_invalidations SnooprTests.mc(x::AbstractFloat, y::Int) = x == y)
    root = only(trees).backedges[1]
    @test length(root.children) == 2
    m = which(SnooprTests.mccc1, (Any, Any))
    ft = findcaller(m, trees)
    fnode = only(ft.backedges)
    while !isempty(fnode.children)
        fnode = only(fnode.children)
    end
    @test fnode.mi.def === m

    # Method deletion
    m = which(SnooprTests.f, (Bool,))
    invs = @snoop_invalidations Base.delete_method(m)
    trees = invalidation_trees(invs)
    tree = only(trees)
    @test tree.reason === :deleting
    @test tree.method == m

    # Method overwriting
    invs = @snoop_invalidations begin
        @eval Module() begin
            Base.@irrational twoπ 6.2831853071795864769 2*big(π)
            Base.@irrational twoπ 6.2831853071795864769 2*big(π)
        end
    end
    # Tabulate invalidations:
    io = IOBuffer()
    SnoopCompile.report_invalidations(io;
        invalidations = invs,
    )
    str = String(take!(io))
    @test occursin("Invalidations %", str)

    trees = invalidation_trees(invs)
    @test length(trees) >= 3
    io = IOBuffer()
    show(io, trees)
    str = String(take!(io))
    @test occursin(r"deleting Float64\(::Irrational{:twoπ}\).*invalidated:\n.*mt_disable: MethodInstance for Float64\(::Irrational{:twoπ}\)", str)
    @test occursin(r"deleting Float32\(::Irrational{:twoπ}\).*invalidated:\n.*mt_disable: MethodInstance for Float32\(::Irrational{:twoπ}\)", str)
    @test occursin(r"deleting BigFloat\(::Irrational{:twoπ}; precision\).*invalidated:\n.*backedges: 1: .*with MethodInstance for BigFloat\(::Irrational{:twoπ}\) \(1 children\)", str)
    # #268
    invs = @snoop_invalidations begin
        @eval Module() begin
            @noinline Base.throw_boundserror(A, I) = throw(BoundsError(A, I))
        end
    end
    trees = invalidation_trees(invs)
    show(io, trees)
    lines = split(String(take!(io)), '\n')
    idx = findfirst(str -> occursin("mt_disable", str), lines)
    if idx !== nothing
        @test occursin("throw_boundserror", lines[idx])
        @test occursin(r"\+\d+ more", lines[idx+1])
    end

    # Exclusion of Core.Compiler methods
    invs = @snoop_invalidations (::Type{T})(x::SnooprTests.MyInt) where T<:Integer = T(x.x)
    umis1 = uinvalidated(invs)
    umis2 = uinvalidated(invs; exclude_corecompiler=false)

    # recursive filtermod
    list = Union{Int,String}[1,2]
    Outer.runop(list)
    invs = @snoop_invalidations Inner.op(a, b::String) = a + length(b)
    trees = invalidation_trees(invs)
    @test length(trees) == 1
    @test length(filtermod(Inner, trees)) == 1
    @test isempty(filtermod(Outer, trees))
    @test length(filtermod(Outer, trees; recursive=true)) == 1
end

@testset "Delayed invalidations" begin
    cproj = Base.active_project()
    cd(joinpath(@__DIR__, "testmodules", "Invalidation")) do
        Pkg.activate(pwd())
        Pkg.develop(path="./PkgC")
        Pkg.develop(path="./PkgD")
        Pkg.precompile()
        invalidations = @snoop_invalidations begin
            @eval begin
                using PkgC
                PkgC.nbits(::UInt8) = 8
                using PkgD
            end
        end
        tree = only(invalidation_trees(invalidations))
        @test tree.reason == :inserting
        @test tree.method.file == Symbol(@__FILE__)
        @test isempty(tree.backedges)
        sig, root = only(tree.mt_backedges)
        @test sig.parameters[1] === typeof(PkgC.nbits)
        @test sig.parameters[2] === Integer
        @test root.mi == first(SnoopCompile.specializations(only(methods(PkgD.call_nbits))))
    end

    Pkg.activate(cproj)
end
