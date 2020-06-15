export @snoopr, invalidation_trees, filtermod, findcaller

dummy() = nothing
dummy()
const dummyinstance = which(dummy, ()).specializations[1]

mutable struct InstanceTree
    mi::MethodInstance
    depth::Int32
    children::Vector{InstanceTree}
    parent::InstanceTree

    # Create a new tree. Creates the root, but returns a leaf.
    # The root is a leaf if `depth = 0`.
    function InstanceTree(mi::MethodInstance, depth)
        tree = new(mi, depth, InstanceTree[])
        child = tree
        while depth > 0
            depth -= 1
            parent = new(dummyinstance, depth, InstanceTree[])
            push!(parent.children, child)
            child.parent = parent
            child = parent
        end
        return tree
    end
    # Create child with a given `parent`. Checks that the depths are consistent.
    function InstanceTree(mi::MethodInstance, parent::InstanceTree, depth)
        @assert parent.depth + Int32(1) == depth
        child = new(mi, depth, InstanceTree[], parent)
        push!(parent.children, child)
        return child
    end
end

function getroot(node::InstanceTree)
    while isdefined(node, :parent)
        node = node.parent
    end
    return node
end

function Base.any(f, node::InstanceTree)
    f(node) && return true
    return any(f, node.children)
end

function Base.show(io::IO, node::InstanceTree; methods=false, maxdepth::Int=5, minchildren::Int=round(Int, sqrt(countchildren(node))))
    if get(io, :limit, false)
        print(io, node.mi, " at depth ", node.depth, " with ", countchildren(node), " children")
    else
        nc = map(countchildren, node.children)
        s = sum(nc) + length(node.children)
        indent = " "^Int(node.depth)
        print(io, indent, methods ? node.mi.def : node.mi)
        println(io, " (", s, " children)")
        p = sortperm(nc)
        skipped = false
        for i in p
            child = node.children[i]
            if child.depth <= maxdepth && nc[i] >= minchildren
                show(io, child; methods=methods, maxdepth=maxdepth, minchildren=minchildren)
            else
                skipped = true
            end
        end
        if skipped
            println(io, indent, "⋮")
            return nothing
        end
    end
end
Base.show(node::InstanceTree; kwargs...) = show(stdout, node; kwargs...)

struct MethodInvalidations
    method::Method
    reason::Symbol   # :insert or :delete
    mt_backedges::Vector{Pair{Any,InstanceTree}}   # sig=>tree
    backedges::Vector{InstanceTree}
    mt_cache::Vector{MethodInstance}
end
methinv_storage() = Pair{Any,InstanceTree}[], InstanceTree[], MethodInstance[]
function MethodInvalidations(method::Method, reason::Symbol)
    MethodInvalidations(method, reason, methinv_storage()...)
end

Base.isempty(inv::MethodInvalidations) = isempty(inv.mt_backedges) && isempty(inv.backedges)  # ignore mt_cache

function countchildren(tree::InstanceTree)
    n = length(tree.children)
    for child in tree.children
        n += countchildren(child)
    end
    return n
end
countchildren(sigtree::Pair{<:Any,InstanceTree}) = countchildren(sigtree.second)

function countchildren(invalidations::MethodInvalidations)
    n = 0
    for list in (invalidations.mt_backedges, invalidations.backedges)
        for tree in list
            n += countchildren(tree)
        end
    end
    return n
end

function Base.sort!(invalidations::MethodInvalidations)
    sort!(invalidations.mt_backedges; by=countchildren)
    sort!(invalidations.backedges; by=countchildren)
    return invalidations
end

# We could use AbstractTrees here, but typically one is not interested in the full tree,
# just the top method and the number of children it has
function Base.show(io::IO, invalidations::MethodInvalidations)
    iscompact = get(io, :compact, false)::Bool
    method = invalidations.method

    function showlist(io, treelist, indent=0)
        nc = map(countchildren, treelist)
        n = length(treelist)
        nd = ndigits(n)
        for i = 1:n
            print(io, lpad(i, nd), ": ")
            tree = treelist[i]
            sig = nothing
            if isa(tree, Pair)
                print(io, "signature ", tree.first, " triggered ")
                sig = tree.first
                tree = tree.second
            else
                print(io, "superseding ", tree.mi.def , " with ")
                sig = tree.mi.def.sig
            end
            print(io, tree.mi, " (", countchildren(tree), " children)")
            if sig !== nothing
                ms1, ms2 = method.sig <: sig, sig <: method.sig
                diagnosis = if ms1 && !ms2
                    "more specific"
                elseif ms2 && !ms1
                    "less specific"
                elseif ms1 && ms1
                    "equal specificity"
                else
                    "ambiguous"
                end
                printstyled(io, ' ', diagnosis, color=:cyan)
            end
            if iscompact
                i < n && print(io, ", ")
            else
                print(io, '\n')
                i < n && print(io, " "^indent)
            end
        end
    end

    println(io, invalidations.reason, " ", invalidations.method, " invalidated:")
    indent = iscompact ? "" : "   "
    for fn in (:mt_backedges, :backedges)
        val = getfield(invalidations, fn)
        if !isempty(val)
            print(io, indent, fn, ": ")
            showlist(io, val, length(indent)+length(String(fn))+2)
        end
        iscompact && print(io, "; ")
    end
    if !isempty(invalidations.mt_cache)
        println(io, indent, length(invalidations.mt_cache), " mt_cache")
    end
    iscompact && print(io, ';')
end

"""
    trees = invalidation_trees(list)

Parse `list`, as captured by [`@snoopr`](@ref), into a set of invalidation trees, where parents nodes
were called by their children.

# Example

```julia
julia> f(x::Int)  = 1
f (generic function with 1 method)

julia> f(x::Bool) = 2
f (generic function with 2 methods)

julia> applyf(container) = f(container[1])
applyf (generic function with 1 method)

julia> callapplyf(container) = applyf(container)
callapplyf (generic function with 1 method)

julia> c = Any[1]
1-element Array{Any,1}:
 1

julia> callapplyf(c)
1

julia> trees = invalidation_trees(@snoopr f(::AbstractFloat) = 3)
1-element Array{SnoopCompile.MethodInvalidations,1}:
 insert f(::AbstractFloat) in Main at REPL[36]:1 invalidated:
   mt_backedges: 1: signature Tuple{typeof(f),Any} triggered MethodInstance for applyf(::Array{Any,1}) (1 children) more specific
```

See the documentation for further details.
"""
function invalidation_trees(list)
    function checkreason(reason, loctag)
        if loctag == "jl_method_table_disable"
            @assert reason === nothing || reason === :delete
            reason = :delete
        elseif loctag == "jl_method_table_insert"
            @assert reason === nothing || reason === :insert
            reason = :insert
        else
            error("unexpected reason ", loctag)
        end
        return reason
    end

    methodinvs = MethodInvalidations[]
    tree = nothing
    mt_backedges, backedges, mt_cache = methinv_storage()
    reason = nothing
    i = 0
    while i < length(list)
        item = list[i+=1]
        if isa(item, MethodInstance)
            mi = item
            item = list[i+=1]
            if isa(item, Int32)
                depth = item
                if tree === nothing
                    tree = InstanceTree(mi, depth)
                else
                    # Recurse back up the tree until we find the right parent
                    while tree.depth >= depth
                        tree = tree.parent
                    end
                    tree = InstanceTree(mi, tree, depth)
                end
            elseif isa(item, String)
                loctag = item
                if loctag == "invalidate_mt_cache"
                    push!(mt_cache, mi)
                    tree = nothing
                elseif loctag == "jl_method_table_insert"
                    tree = getroot(tree)
                    tree.mi = mi
                    push!(backedges, tree)
                    tree = nothing
                elseif loctag == "insert_backedges"
                    println("insert_backedges for ", mi)
                else
                    error("unexpected loctag ", loctag, " at ", i)
                end
            else
                error("unexpected item ", item, " at ", i)
            end
        elseif isa(item, Method)
            method = item
            isassigned(list, i+1) || @show i
            item = list[i+=1]
            if isa(item, String)
                reason = checkreason(reason, item)
                push!(methodinvs, sort!(MethodInvalidations(method, reason, mt_backedges, backedges, mt_cache)))
                mt_backedges, backedges, mt_cache = methinv_storage()
                tree = nothing
            else
                error("unexpected item ", item, " at ", i)
            end
        elseif isa(item, String)
            # This shouldn't happen
            reason = checkreason(reason, item)
            push!(backedges, getroot(tree))
            tree = nothing
        elseif isa(item, Type)
            push!(mt_backedges, item=>getroot(tree))
            tree = nothing
        else
            error("unexpected item ", item, " at ", i)
        end
    end
    return sort!(methodinvs; by=countchildren)
end

"""
    thinned = filtermod(module, trees::AbstractVector{MethodInvalidations})

Select just the cases of invalidating a method defined in `module`.
"""
function filtermod(mod::Module, trees::AbstractVector{MethodInvalidations})
    # We don't just broadcast because we want to filter at all levels
    thinned = MethodInvalidations[]
    for invs in trees
        _invs = filtermod(mod, invs)
        isempty(_invs) || push!(thinned, _invs)
    end
    return sort!(thinned; by=countchildren)
end

function filtermod(mod::Module, invs::MethodInvalidations)
    hasmod(mod, node::InstanceTree) = node.mi.def.module === mod

    mt_backedges = filter(pr->hasmod(mod, pr.second), invs.mt_backedges)
    backedges = filter(tree->hasmod(mod, tree), invs.backedges)
    return MethodInvalidations(invs.method, invs.reason, mt_backedges, backedges, copy(invs.mt_cache))
end

"""
    invs = findcaller(method::Method, trees)

Find a path through `trees` that reaches `method`. Returns a single `MethodInvalidations` object.

# Examples

Suppose you know that loading package `SomePkg` triggers invalidation of `f(data)`.
You can find the specific source of invalidation as follows:

```
f(data)                             # run once to force compilation
m = @which f(data)
using SnoopCompile
trees = invalidation_trees(@snoopr using SomePkg)
invs = findcaller(m, trees)
```

If you don't know which method to look for, but know some operation that has had added latency,
you can look for methods using `@snoopi`. For example, suppose that loading `SomePkg` makes the
next `using` statement slow. You can find the source of trouble with

```
julia> using SnoopCompile

julia> trees = invalidation_trees(@snoopr using SomePkg);

julia> tinf = @snoopi using SomePkg            # this second `using` will need to recompile code invalidated above
1-element Array{Tuple{Float64,Core.MethodInstance},1}:
 (0.08518409729003906, MethodInstance for require(::Module, ::Symbol))

julia> m = tinf[1][2].def
require(into::Module, mod::Symbol) in Base at loading.jl:887

julia> findcaller(m, trees)
insert ==(x, y::SomeType) in SomeOtherPkg at /path/to/code:100 invalidated:
   backedges: 1: superseding ==(x, y) in Base at operators.jl:83 with MethodInstance for ==(::Symbol, ::Any) (16 children) more specific
```
"""
function findcaller(meth::Method, trees::AbstractVector{MethodInvalidations})
    for tree in trees
        ret = findcaller(meth, tree)
        ret === nothing || return ret
    end
    return nothing
end

function findcaller(meth::Method, invs::MethodInvalidations)
    function newtree(vectree)
        root0 = pop!(vectree)
        root = InstanceTree(root0.mi, root0.depth)
        return newtree!(root, vectree)
    end
    function newtree!(parent, vectree)
        isempty(vectree) && return getroot(parent)
        child = pop!(vectree)
        newp = InstanceTree(child.mi, parent, child.depth)
        return newtree!(newp, vectree)
    end

    for (sig, node) in invs.mt_backedges
        ret = findcaller(meth, node)
        ret === nothing && continue
        return MethodInvalidations(invs.method, invs.reason, [Pair{Any,InstanceTree}(sig, newtree(ret))], InstanceTree[], copy(invs.mt_cache))
    end
    for node in invs.backedges
        ret = findcaller(meth, node)
        ret === nothing && continue
        return MethodInvalidations(invs.method, invs.reason, Pair{Any,InstanceTree}[], [newtree(ret)], copy(invs.mt_cache))
    end
    return nothing
end

function findcaller(meth::Method, tree::InstanceTree)
    meth === tree.mi.def && return [tree]
    for child in tree.children
        ret = findcaller(meth, child)
        if ret !== nothing
            push!(ret, tree)
            return ret
        end
    end
    return nothing
end

"""
    list = @snoopr expr

Capture method cache invalidations triggered by evaluating `expr`.
`list` is a sequence of invalidated `Core.MethodInstance`s together with "explanations," consisting
of integers (encoding depth) and strings (documenting the source of an invalidation).

Unless you are working at a low level, you essentially always want to pass `list`
directly to [`invalidation_trees`](@ref).

# Extended help

`list` is in a format where the "reason" comes after the items.
Method deletion results in the sequence

    [zero or more (mi, "invalidate_mt_cache") pairs..., zero or more (depth1 tree, loctag) pairs..., method, loctag] with loctag = "jl_method_table_disable"

where `mi` means a `MethodInstance`. `depth1` means a sequence starting at `depth=1`.

Method insertion results in the sequence

    [zero or more (depth0 tree, sig) pairs..., same info as with delete_method except loctag = "jl_method_table_insert"]
"""
macro snoopr(expr)
    quote
        local invalidations = ccall(:jl_debug_method_invalidation, Any, (Cint,), 1)
        Expr(:tryfinally,
            $(esc(expr)),
            ccall(:jl_debug_method_invalidation, Any, (Cint,), 0)
        )
        invalidations
    end
end
