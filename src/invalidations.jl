export @snoopr, invalidation_trees, filtermod

dummy() = nothing
dummy()
const dummyinstance = which(dummy, ()).specializations[1]

mutable struct InstanceTree
    mi::MethodInstance
    depth::Int32
    children::Vector{InstanceTree}
    parent::InstanceTree

    # Create tree root, but return a leaf
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
    # Create child
    function InstanceTree(mi::MethodInstance, parent::InstanceTree, depth)
        @assert parent.depth + Int32(1) == depth
        new(mi, depth, InstanceTree[], parent)
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

# `list` is in RPN format, with the "reason" coming after the items
# Here is a brief summary of the cause and resulting entries
# delete_method:
#   [zero or more (mi, "invalidate_mt_cache") pairs..., zero or more (depth1 tree, loctag) pairs..., method, loctag] with loctag = "jl_method_table_disable"
# method insertion:
#   [zero or more (depth0 tree, sig) pairs..., same info as with delete_method except loctag = "jl_method_table_insert"]

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
                    newtree = InstanceTree(mi, tree, depth)
                    push!(tree.children, newtree)
                    tree = newtree
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
