using SnoopCompile, InteractiveUtils, MethodAnalysis, Test

const qualify_mi = Base.VERSION >= v"1.7.0-DEV.5"  # julia PR #38608

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


@testset "@snoopr" begin
    prefix = qualify_mi ? "$(@__MODULE__).SnooprTests." : ""

    c = Any[1]
    @test SnooprTests.callapplyf(c) == 1
    mi1 = methodinstance(SnooprTests.applyf, (Vector{Any},))
    mi2 = methodinstance(SnooprTests.callapplyf, (Vector{Any},))

    invs = @snoopr SnooprTests.f(::AbstractFloat) = 3
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
    invs = @snoopr SnooprTests.f(::Float32) = 4
    @test !isempty(invs)
    trees = invalidation_trees(invs)

    methinvs = only(trees)
    m = which(SnooprTests.f, (Float32,))
    # These next are identical to the above
    @test methinvs.method == m
    @test methinvs.reason === :inserting
    root = only(methinvs.backedges)
    @test root.mi == mi3
    @test SnoopCompile.getroot(root) === root
    @test root.depth == 0
    child = only(root.children)
    @test child.mi == mi1
    @test SnoopCompile.getroot(child) === root
    @test child.depth == 1
    if isempty(child.children)
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
    @test occursin("backedges: 1: superseding f(::AbstractFloat)", str)
    @test occursin("with MethodInstance for $(prefix)f(::AbstractFloat) ($targetdepth children)", str)

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

    ftrees = filtermod(@__MODULE__, trees)
    ftree = only(ftrees)
    @test ftree.backedges == methinvs.backedges
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
    invs = @snoopr Base.delete_method(m)
    trees = invalidation_trees(invs)
    tree = only(trees)
    @test tree.reason === :deleting
    @test tree.method == m

    # Method overwriting
    invs = @snoopr begin
        @eval Module() begin
            Base.@irrational twoπ 6.2831853071795864769 2*big(π)
            Base.@irrational twoπ 6.2831853071795864769 2*big(π)
        end
    end
    trees = invalidation_trees(invs)
    @test length(trees) == 3
    io = IOBuffer()
    show(io, trees)
    str = String(take!(io))
    @test occursin(r"deleting Float64\(::Irrational{:twoπ}\).*invalidated:\n.*mt_disable: MethodInstance for Float64\(::Irrational{:twoπ}\)", str)
    @test occursin(r"deleting Float32\(::Irrational{:twoπ}\).*invalidated:\n.*mt_disable: MethodInstance for Float32\(::Irrational{:twoπ}\)", str)
    @test occursin(r"deleting BigFloat\(::Irrational{:twoπ}; precision\).*invalidated:\n.*backedges: 1: .*with MethodInstance for BigFloat\(::Irrational{:twoπ}\) \(1 children\)", str)

    # Exclusion of Core.Compiler methods
    invs = @snoopr (::Type{T})(x::SnooprTests.MyInt) where T<:Integer = T(x.x)
    umis1 = uinvalidated(invs)
    umis2 = uinvalidated(invs; exclude_corecompiler=false)
    @test length(umis2) > length(umis1) + 20

    # recursive filtermod
    list = Union{Int,String}[1,2]
    Outer.runop(list)
    invs = @snoopr Inner.op(a, b::String) = a + length(b)
    trees = invalidation_trees(invs)
    @test length(trees) == 1
    @test length(filtermod(Inner, trees)) == 1
    @test isempty(filtermod(Outer, trees))
    @test length(filtermod(Outer, trees; recursive=true)) == 1
end

@testset "Delayed invalidations" begin
    if Base.VERSION >= v"1.7.0-DEV.254"   # julia#39132 (redirect to Pipe)
        # "Natural" tests are performed in the "Stale" testset of "snoopi_deep.jl"
        # because they are also used for precompile_blockers.
        # Here we craft them artificially.
        M = @eval Module() begin
            fake1(x) = 1
            fake2(x) = fake1(x)
            foo() = nothing
            @__MODULE__
        end
        M.fake2('a')
        callee = methodinstance(M.fake1, (Char,))
        caller = methodinstance(M.fake2, (Char,))
        # failed attribution (no invalidations occurred prior to the backedges invalidations)
        invalidations = Any[callee, "insert_backedges_callee", caller, "insert_backedges"]
        pipe = Pipe()
        redirect_stdout(pipe) do
            @test_logs (:warn, "Could not attribute the following delayed invalidations:") begin
                trees = invalidation_trees(invalidations)
                @test isempty(trees)
            end
        end
        close(pipe.in)
        str = read(pipe.out, String)
        @test occursin(r"fake1\(::Char\).*invalidated.*fake2\(::Char\)", str)

        m = which(M.foo, ())
        invalidations = Any[Any[caller, Int32(1), callee, "jl_method_table_insert", m, "jl_method_table_insert"]; invalidations]
        tree = @test_nowarn only(invalidation_trees(invalidations))
        @test tree.method == m
        @test tree.reason == :inserting
        mi1, mi2 = tree.mt_backedges[1]
        @test mi1 == callee
        @test mi2 == caller
        @test Core.MethodInstance(tree.backedges[1]) == callee
    end
end
