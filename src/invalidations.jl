export uinvalidated, invalidation_trees, filtermod, findcaller

function from_corecompiler(mi::MethodInstance)
    fn = fullname(mi.def.module)
    length(fn) < 2 && return false
    fn[1] === :Core || return false
    return fn[2] === :Compiler
end

"""
    umis = uinvalidated(invlist)

Return the unique invalidated MethodInstances. `invlist` is obtained from [`SnoopCompileCore.@snoop_invalidations`](@ref).
This is similar to `filter`ing for `MethodInstance`s in `invlist`, except that it discards any tagged
`"invalidate_mt_cache"`. These can typically be ignored because they are nearly inconsequential:
they do not invalidate any compiled code, they only transiently affect an optimization of runtime dispatch.
"""
function uinvalidated(invlist; exclude_corecompiler::Bool=true)
    umis = Set{MethodInstance}()
    i, ilast = firstindex(invlist), lastindex(invlist)
    while i <= ilast
        item = invlist[i]
        if isa(item, CodeInstance)
            item = methodinstance(item)
        end
        if isa(item, MethodInstance)
            if i < lastindex(invlist)
                if invlist[i+1] == "invalidate_mt_cache"
                    i += 2
                    continue
                end
                if invlist[i+1] == "verify_methods"
                    # Skip over the cause, which can also be a MethodInstance
                    # These may be superseded, but they aren't technically invalidated
                    # (e.g., could still be called via `invoke`)
                    i += 2
                end
            end
            if !exclude_corecompiler || !from_corecompiler(item)
                push!(umis, item)
            end
        end
        i += 1
    end
    return umis
end

# Variable names:
# - `node`, `root`, `leaf`, `parent`, `child`: all `InstanceNode`s, a.k.a. nodes in a MethodInstance tree
# - `methinvs::InvalidationTree`: the set of invalidations that occur from inserting or deleting a method
# - `trees`: a list of `methinvs`

dummy() = nothing
dummy()
const dummyinstance = first(specializations(which(dummy, ()))).cache

struct BackEdge
    sig::Union{DataType,Nothing}   # call signature from `invoke` or abstract call; nothing for concrete or a "covered" abstract call
    instance::Union{MethodInstance,CodeInstance}
end
BackEdge(instance::Union{MethodInstance,CodeInstance}) = BackEdge(nothing, instance)

const dummyedge = BackEdge(dummyinstance)

function Base.show(io::IO, edge::BackEdge)
    if edge.sig !== nothing
        show(io, edge.sig)
        print(io, " => ")
    end
    show(io, methodinstance(edge.instance))
end

abstract type AbstractTreeNode end

mutable struct InstanceNode <: AbstractTreeNode
    edge::BackEdge
    depth::Int32
    children::Vector{InstanceNode}
    parent::InstanceNode

    # Create a new tree. Creates the `root` with depth=0, but returns the `leaf` holding `edge`.
    # `root == leaf` if `depth = 0`, otherwise parent "dummy" nodes are inserted.
    function InstanceNode(edge::BackEdge, depth)
        leaf = new(edge, depth, InstanceNode[])
        child = leaf
        while depth > 0
            depth -= 1
            parent = new(dummyedge, depth, InstanceNode[])
            push!(parent.children, child)
            child.parent = parent
            child = parent
        end
        return leaf
    end
    function InstanceNode(edge::BackEdge, children::Vector{InstanceNode})
        # re-parent "children"
        root = new(edge, 0, children)
        for child in children
            child.parent = root
        end
        return root
    end
    # Create child with a given `parent`. Checks that the depths are consistent.
    function InstanceNode(edge::BackEdge, parent::InstanceNode, depth=parent.depth+Int32(1))
        @assert parent.depth + Int32(1) == depth
        child = new(edge, depth, InstanceNode[], parent)
        push!(parent.children, child)
        return child
    end
    # Creating a tree, starting with the leaves (omits `parent`)
    function InstanceNode(node::InstanceNode, newchildren::Vector{InstanceNode})
        @assert all(child -> child.depth == node.depth + Int32(1), newchildren)
        parent = new(node.edge, node.depth, newchildren)
        for child in newchildren
            child.parent = parent
        end
        return parent
    end
end

isdummy(node::InstanceNode) = node.edge === dummyedge

Core.MethodInstance(node::InstanceNode) = methodinstance(node.edge.instance)
Base.convert(::Type{MethodInstance}, node::InstanceNode) = MethodInstance(node)

AbstractTrees.children(node::InstanceNode) = node.children
AbstractTrees.nodevalue(node::InstanceNode) = node.edge
AbstractTrees.parent(node::InstanceNode) = node.parent
AbstractTrees.childtype(::Type{InstanceNode}) = InstanceNode
AbstractTrees.ParentLinks(::Type{InstanceNode}) = AbstractTrees.StoredParents()
AbstractTrees.ChildIndexing(::Type{InstanceNode}) = AbstractTrees.IndexedChildren()
AbstractTrees.NodeType(::Type{InstanceNode}) = AbstractTrees.HasNodeType()
AbstractTrees.isroot(node::InstanceNode) = !isdefined(node, :parent)
AbstractTrees.ischild(node1::InstanceNode, node2::InstanceNode) = !isroot(node1) && node1.parent === node2
function AbstractTrees.intree(node::InstanceNode, root::InstanceNode)
    while !isroot(node)
        node === root && return true
        node = node.parent
    end
    return false
end
function AbstractTrees.getroot(node::InstanceNode)
    while isdefined(node, :parent)
        node = node.parent
    end
    return node
end
function AbstractTrees.printnode(io::IO, node::InstanceNode)
    print(io, nodevalue(node), " at depth ", node.depth, " with ", countchildren(node), " children")
end
Base.show(io::IO, node::InstanceNode) = AbstractTrees.printnode(io, node)

function Base.any(f, node::InstanceNode)
    f(node) && return true
    return any(f, node.children)
end

function Base.sort!(node::AbstractTreeNode)
    sort!(node.children; by=countchildren)
    for child in node.children
        sort!(child)
    end
end

function copybranch(node::InstanceNode)
    children = InstanceNode[copybranch(child) for child in node.children]
    return InstanceNode(node, children)
end

function countchildren(node::AbstractTreeNode)
    n = length(node.children)
    for child in node.children
        n += countchildren(child)
    end
    return n
end

function adjust_depth!(node::InstanceNode, Δdepth)
    node.depth += Δdepth
    for child in node.children
        adjust_depth!(child, Δdepth)
    end
    return node
end

abstract type AbstractInvalidationTree end

struct InvalidationTree <: AbstractInvalidationTree
    cause::Union{Method,BindingPartition}
    reason::Symbol   # :inserting, :deleting, or :modifying
    backedges::Vector{InstanceNode}
    mt_cache::Vector{MethodInstance}
    mt_disable::Vector{MethodInstance}
end
methinv_storage() = InstanceNode[], MethodInstance[], MethodInstance[]
function InvalidationTree(cause::Union{Method,BindingPartition}, reason::Symbol)
    InvalidationTree(cause, reason, methinv_storage()...)
end

Base.isempty(methinvs::InvalidationTree) = isempty(methinvs.backedges)  # ignore mt_cache and mt_disable

function Base.:(==)(methinvs1::InvalidationTree, methinvs2::InvalidationTree)
    methinvs1.cause == methinvs2.cause || return false
    methinvs1.reason == methinvs2.reason || return false
    methinvs1.backedges == methinvs2.backedges || return false
    methinvs1.mt_cache == methinvs2.mt_cache || return false
    methinvs1.mt_disable == methinvs2.mt_disable || return false
    return true
end

countchildren(mmi::AbstractInvalidationTree) = sum(countchildren, mmi.backedges; init=0)

function Base.sort!(methinvs::AbstractInvalidationTree)
    sort!(methinvs.backedges; by=countchildren)
    # recursive
    for root in methinvs.backedges
        sort!(root)
    end
    return methinvs
end

# We could use AbstractTrees here, but typically one is not interested in the full tree,
# just the top method and the number of children it has
function Base.show(io::IO, methinvs::InvalidationTree)
    iscompact = get(io, :compact, false)::Bool

    print(io, methinvs.reason, " ")
    cause = methinvs.cause
    if isa(cause, Method)
        printstyled(io, cause, color = :light_magenta)
    else
        Base.with_output_color(:light_magenta, io, methinvs.cause) do io, x
            show(io, MIME("text/plain"), x)
        end
    end
    println(io, " invalidated:")
    indent = iscompact ? "" : "   "
    if !isempty(methinvs.backedges)
        print(io, indent, "backedges: ")
        showlist(io, methinvs.backedges, length(indent)+length("backedges")+2)
    end
    if !isempty(methinvs.mt_disable)
        print(io, indent, "mt_disable: ")
        println(io, first(methinvs.mt_disable))
        if length(methinvs.mt_disable) > 1
            println(io, indent, " "^12, "+", length(methinvs.mt_disable)-1, " more")
        end
    end
    if !isempty(methinvs.mt_cache)
        println(io, indent, length(methinvs.mt_cache), " mt_cache")
    end
    iscompact && print(io, ';')
end

function showlist(io::IO, treelist, indent::Int=0)
    iscompact = get(io, :compact, false)::Bool

    n = length(treelist)
    nd = ndigits(n)
    for i = 1:n
        print(io, lpad(i, nd), ": ")
        root = treelist[i]
        sig, instance = getsigedge(root)
        if sig !== nothing
            print(io, "signature ")
            printstyled(io, sig, color = :light_cyan)
            print(io, " => ")
        end
        if isa(instance, Vector{CodeInstance})
            print(io, "CodeInstance[")
            firstci = true
            for ci in instance
                firstci || print(io, ", ")
                printstyled(io, methodinstance(ci), color = :light_yellow)
                firstci = false
            end
            print(io, "]")
        else
            printstyled(io, methodinstance(instance), color = :light_yellow)
        end
        print(io, " (", countchildren(root), " children)")
        if iscompact
            i < n && print(io, ", ")
        else
            print(io, '\n')
            i < n && print(io, " "^indent)
        end
    end
end

function getsigedge(node::InstanceNode)
    edge = node.edge
    (; sig, instance) = edge
    return sig, instance
end

"""
    report_invalidations(
        io::IO = stdout;
        invalidations,
        n_rows::Int = 10,
        process_filename::Function = x -> x,
    )

Print a tabular summary of invalidations given:

 - `invalidations` the output of [`SnoopCompileCore.@snoop_invalidations`](@ref)

and (optionally)

 - `io::IO` IO stream. Defaults to `stdout`
 - `n_rows::Int` the number of rows to be displayed in the
   truncated table. A value of 0 indicates no truncation.
   A positive value will truncate the table to the specified
   number of rows.
 - `process_filename(::String)::String` a function to post-process
   each filename, where invalidations are found

# Example usage

```julia
import SnoopCompileCore
invalidations = SnoopCompileCore.@snoop_invalidations begin

    # load packages & define any additional methods

end;

using SnoopCompile
using PrettyTables # to load report_invalidations
report_invalidations(;invalidations)
```

Using `report_invalidations` requires that you first load the `PrettyTables.jl` package.
"""
function report_invalidations end

function invalidation_trees_logmeths(list; exclude_corecompiler::Bool=true)
    methodinvs = InvalidationTree[]
    backedges, mt_cache, mt_disable = methinv_storage()
    reason = parent = nothing
    i = 0
    while i < length(list)
        @show i parent
        invokesig = nothing
        item = list[i+=1]
        if !isa(item, MethodInstance) && !isa(item, CodeInstance) && !isa(item, Method) && !isa(item, BindingPartition)
            invokesig = item
            item = list[i+=1]
        end
        @show invokesig item
        if isa(item, CodeInstance)
            edge = BackEdge(invokesig, item)
            @show edge
            item = list[i+=1]
            @assert isa(item, Int32)
            depth = item
            @assert !iszero(depth)
            if parent === nothing
                parent = InstanceNode(edge, depth)
            else
                while depth < parent.depth + 1 # && isdefined(parent, :parent)
                    parent = parent.parent
                end
                parent = InstanceNode(edge, parent, depth)
            end
        elseif isa(item, MethodInstance)
            edge = BackEdge(invokesig, item)
            item = list[i+=1]
            @assert isa(item, String)
            if item ∈ ("jl_method_table_insert", "jl_method_table_disable")
                if parent === nothing
                    root = InstanceNode(edge, 0)
                else
                    root = getroot(parent)
                    root = InstanceNode(edge, root.children)
                end
                push!(backedges, root)
                parent = nothing
            elseif item == "invalidate_mt_cache"
                @assert edge.sig === nothing
                push!(mt_cache, edge.instance)
            else
                error("not handled yet: ", item)
            end
        # else

        #     elseif isa(item, String)
        #         if item == "invalidate_mt_cache"
        #             push!(mt_cache, edge)
        #         else
        #             @show item
        #             # finish a backedges
        #             reason = checkreason(reason, item)
        #             if parent !== nothing
        #                 @assert isdummy(getroot(parent))
        #             end
        #             root = parent === nothing ? InstanceNode(edge, 0) : InstanceNode(edge, getroot(parent).children)
        #             push!(backedges, root)
        #             parent = nothing
        #         end
        #     end
        # elseif isa(item, Type) && item <: Tuple
        #     error("this shouldn't happen")
        #     # finish an mt_backedges
        #     rootsig = item
        #     root = getroot(parent)
        #     @assert !isdummy(root)
        #     push!(mt_backedges, rootsig=>root)
        #     parent = nothing
        elseif isa(item, Method) || isa(item, BindingPartition)
            cause = item
            if parent !== nothing
                @assert isdummy(getroot(parent))
                push!(backedges, getroot(parent))
                parent = nothing
            end
            item = list[i+=1]
            @assert isa(item, String)
            reason = checkreason(reason, item)
            methinv = InvalidationTree(cause, reason, backedges, mt_cache, mt_disable)
            push!(methodinvs, methinv)
            parent = reason = nothing
            backedges, mt_cache, mt_disable = methinv_storage()
        else
            error("not handled: ", item)
        end
    end
    @assert isempty(backedges) && isempty(mt_cache) && isempty(mt_disable)
    @assert parent === nothing
    return methodinvs
end

const EdgeNodeType = Union{DataType, Binding, MethodInstance, CodeInstance}

struct EdgeRef
    ci::CodeInstance
    edgeidx::Int         # starting index of the edge in `ci.edges`
end

function getsigedge(edgeref::EdgeRef)
    (; ci, edgeidx) = edgeref
    edges = ci.edges
    sig = nothing
    edge = edges[edgeidx]
    isa(edge, CodeInstance) && return sig, edge
    if isa(edge, DataType)
        sig = edge
        edge = edges[edgeidx+1]
        return sig, edge
    elseif isa(edge, Int)
        n = edge
        sig = edges[edgeidx+1]
        cis = CodeInstance[]
        for j in 1:n
            push!(cis, edges[edgeidx+j+1])
        end
        return sig, cis
    end
    error("not handled yet: ", edge)
end

struct EdgeRefNode <: AbstractTreeNode
    edge::EdgeRef
    children::Vector{EdgeRefNode}
    parent::EdgeRefNode

    EdgeRefNode(edge::EdgeRef) = new(edge, EdgeRefNode[])    # create root
    function EdgeRefNode(edge::EdgeRef, parent::EdgeRefNode)
        child = new(edge, EdgeRefNode[], parent)    # create child
        push!(parent.children, child)
        return child
    end
end

getsigedge(node::EdgeRefNode) = getsigedge(node.edge)

struct MultiMethodInvalidations <: AbstractInvalidationTree
    cause::Union{Binding,Vector{Method}}
    backedges::Vector{EdgeRefNode}
end
MultiMethodInvalidations(cause) = MultiMethodInvalidations(cause, EdgeRefNode[])

function Base.show(io::IO, methinvs::MultiMethodInvalidations)
    iscompact = get(io, :compact, false)::Bool

    print(io, "Invalidating cause: ")
    ms = methinvs.cause
    if isa(ms, Vector{Method})
        firstm = true
        for m in methinvs.cause
            firstm || print(io, ", ")
            printstyled(io, m, color = :light_magenta)
            firstm = false
        end
    else
        printstyled(io, ms.globalref, color = :light_red)
    end
    println(io)
    indent = iscompact ? "" : "   "
    if !isempty(methinvs.backedges)
        print(io, indent, "backedges: ")
        showlist(io, methinvs.backedges, length(indent)+length("backedges")+2)
    end
    iscompact && print(io, ';')
end

function invalidation_trees_logedges(list; exclude_corecompiler::Bool=true)
    trees = MultiMethodInvalidations[]
    treeidx = Dict{Union{Binding,Vector{Method}},Int}()
    edgelink = Dict{CodeInstance,EdgeRefNode}()
    i = 0
    while i < length(list)
        op = list[i+=1]::String
        if op == "invalidate_edge"
            cause = list[i+3]::Union{Binding,Vector{Any}}
            if isa(cause, Vector{Any})
                cause = convert(Vector{Method}, cause)
            end
            idx = get(treeidx, cause, nothing)
            if idx === nothing
                mminv = MultiMethodInvalidations(cause)
                push!(trees, mminv)
                idx = length(trees)
                treeidx[cause] = idx
            else
                mminv = trees[idx]
            end
            ci = list[i+1]::CodeInstance
            j = list[i+2]::Int
            @assert 0 < j <= length(ci.edges)
            root = EdgeRefNode(EdgeRef(ci, j))
            push!(mminv.backedges, root)
            empty!(edgelink)
            edgelink[ci] = root
            i += 3
        elseif op == "verify_methods"
            ci = list[i+1]::CodeInstance
            j = list[i+2]::Int
            @assert 0 < j <= length(ci.edges)
            pci = getedgeci(ci.edges, j)
            parent = edgelink[pci]
            child = EdgeRefNode(EdgeRef(ci, j), parent)
            edgelink[ci] = child
            i += 2
        elseif op == "method_globalref"
            error("not implemented yet")
            i += 2
        else
            error("unknown operation ", op)
        end
    end
    return trees
end

function getedgeci(edges::Core.SimpleVector, j::Int)
    while j <= length(edges)
        item = edges[j]
        if isa(item, CodeInstance)
            return item
        end
        j += 1
    end
    error("no CodeInstance found in edges")
end



#     # transiently we represent the graph as a flat list of nodes, a flat list of children indexes, and a Dict to look up the node index
#     nodes = EdgeNodeType[]
#     calleridxss = Vector{Int}[]
#     nodeidx = IdDict{EdgeNodeType,Int}()    # get the index within `nodes` for a given key
#     matchess = Dict{Int,Vector{Method}}()   # nodeidx => Method[...]

#     function addnode(item)
#         push!(nodes, item)
#         k = length(nodes)
#         nodeidx[item] = k
#         return k
#     end

#     function addcaller!(listlist, (calleridx, calleeidx))
#         if length(listlist) < calleeidx
#             resize!(listlist, calleeidx)
#         end
#         # calleridxs = get!(Vector{Int}, listlist, calleeidx)   # why don't we have this??
#         calleridxs = if isassigned(listlist, calleeidx)
#             listlist[calleeidx]
#         else
#             listlist[calleeidx] = Int[]
#         end
#         push!(calleridxs, calleridx)
#         return calleridxs
#     end

#     i = 0
#     while i + 2 < length(list)
#         tag = list[i+2]::String
#         if tag == "method_globalref"
#             def, target = list[i+1]::Method, list[i+3]::CodeInstance
#             i += 4
#             error("implement me")
#         elseif tag == "insert_backedges_callee"
#             edge, target, matches = list[i+1]::EdgeNodeType, list[i+3]::CodeInstance, list[i+4]::Union{Vector{Any},Nothing}
#             i += 4
#             idx = get(nodeidx, edge, nothing)
#             if idx === nothing
#                 idx = addnode(edge)
#                 if matches !== nothing
#                     matchess[idx] = matches
#                 end
#             elseif matches !== nothing
#                 @assert matchess[idx] == matches
#             end
#             idxt = get(nodeidx, target, nothing)
#             @assert idxt === nothing
#             idxt = addnode(target)
#             addcaller!(calleridxss, idxt => idx)
#         elseif tag == "verify_methods"
#             caller, callee = list[i+1]::CodeInstance, list[i+3]::CodeInstance
#             i += 3
#             idxt = get(nodeidx, caller, nothing)
#             if idxt === nothing
#                 idxt = addnode(caller)
#             end
#             idx = get(nodeidx, callee, nothing)
#             if idx === nothing
#                 idx = addnode(callee)
#             end
#             @assert idxt >= idx
#             idxt > idx && addcaller!(calleridxss, idxt => idx)
#         else
#             error("tag ", tag, " unknown")
#         end
#     end
#     return mmi_trees!(nodes, calleridxss, matchess)
# end

function mmi_trees!(nodes::AbstractVector{EdgeNodeType}, calleridxss::Vector{Vector{Int}}, matchess::AbstractDict{Int,Vector{Method}})
    iscaller = BitSet()

    function filltree!(mminvs::MultiMethodInvalidations, i::Int)
        node = nodes[i]
        calleridxs = calleridxss[i]
        if isa(node, Union{DataType,Binding})
            while !isempty(calleridxs)
                j = pop!(calleridxs)
                push!(iscaller, j)
                root = InstanceNode(nodes[j], 0)
                push!(mminvs.mt_backedges, node => root)
                fillnode!(root, j)
            end
        else
            root = InstanceNode(node, 0)
            push!(mminvs.backedges, root)
            fillnode!(root, i)
        end
        return mminvs
    end

    function fillnode!(node::InstanceNode, k)
        calleridxs = isassigned(calleridxss, k) ? calleridxss[k] : nothing
        calleridxs === nothing && return
        while !isempty(calleridxs)
            j = pop!(calleridxs)
            push!(iscaller, j)
            child = InstanceNode(nodes[j], node)
            fillnode!(child, j)
        end
    end

    mminvs = MultiMethodInvalidations[]
    treeindex = Dict{Vector{Method},Int}()
    for i in eachindex(nodes)
        if i ∉ iscaller
            node = nodes[i]
            arg = get(matchess, i, node)
            j = get(treeindex, arg, nothing)
            if j === nothing
                mminv = MultiMethodInvalidations(arg)
                push!(mminvs, mminv)
                j = length(mminvs)
                treeindex[arg] = j
            else
                mminv = mminvs[j]
            end
            filltree!(mminv, i)
        else
            @assert !isassigned(calleridxss, i) || isempty(calleridxss[i])
        end
    end
    return mminvs
end

"""
    trees = invalidation_trees(list; consolidate=true)

Parse `list`, as captured by [`SnoopCompileCore.@snoop_invalidations`](@ref),
into a set of invalidation trees, where parents nodes were called by their
children.

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

julia> trees = invalidation_trees(@snoop_invalidations f(::AbstractFloat) = 3)
1-element Array{SnoopCompile.InvalidationTree,1}:
 inserting f(::AbstractFloat) in Main at REPL[36]:1 invalidated:
   mt_backedges: 1: signature Tuple{typeof(f),Any} triggered MethodInstance for applyf(::Array{Any,1}) (1 children) more specific
```

There are two sources of invalidation: method insertion/deletion (new code
invalidating old code) and edge validation (package import validating against
the existing session). By default, these two are combined into a single set of
trees, but you can disable this by passing `consolidate=false`. One potential
advantage of not consolidating is that edge-validation can bundle multiple
methods together into a single invalidation tree, which might reduce the number
of trees if a package creates many methods for a single function.

For more information, see the tutorials in the online documentation.
"""
function invalidation_trees(list::InvalidationLists; consolidate::Bool=true, kwargs...)
    mtrees = invalidation_trees_logmeths(list.logmeths; kwargs...)
    etrees = invalidation_trees_logedges(list.logedges; kwargs...)
    if !consolidate
        trees = [mtrees; etrees]
    else
        trees = mtrees
        mindex = Dict(tree.cause => i for (i, tree) in enumerate(mtrees))  # map method to index in mtrees
        for etree in etrees
            methods = etree.methods
            if isa(methods, Vector{Method})
                for method in methods
                    # Check if this method already exists in mtrees
                    idx = get(mindex, method, nothing)
                    if idx !== nothing
                        # Merge the trees
                            join_invalidations!(trees[idx].mt_backedges, etree.mt_backedges)
                            join_invalidations!(trees[idx].backedges, etree.backedges)
                    else
                        # Otherwise just add it to the list
                        push!(trees, InvalidationTree(
                            method,
                            :inserting,
                            copy(etree.mt_backedges),
                            copy(etree.backedges),
                            MethodInstance[],  # mt_cache
                            MethodInstance[]   # mt_disable
                        ))
                        mindex[method] = length(trees)
                    end
                end
            else
                display(etree)
                error("fixme")
            end
        end
    end
    for tree in trees
        sort!(tree)
    end
    sort!(trees; by=countchildren)
    return trees
end

# These make testing a lot easier
function firstmatch(trees::AbstractVector{InvalidationTree}, m::Method)
    for tree in trees
        tree.cause === m && return tree
    end
    error("no tree found for method ", m)
end

# function firstmatch(mt_backedges::AbstractVector{BackedgeMT}, @nospecialize(sig::Type))
#     for (_sig, root) in mt_backedges
#         _sig === sig && return sig, root
#     end
#     error("no root found for signature ", sig)
# end

function firstmatch(backedges::AbstractVector{InstanceNode}, mi::MethodInstance)
    for root in backedges
        root.mi === mi && return root
    end
    error("no node found for MethodInstance ", mi)
end

function firstmatch(backedges::AbstractVector{InstanceNode}, @nospecialize(sig::Type))
    for root in backedges
        root.mi.specTypes === sig && return root
    end
    error("no node found for signature ", sig)
end

function firstmatch(backedges::AbstractVector{InstanceNode}, m::Method)
    for root in backedges
        root.mi.def === m && return root
    end
    error("no node found for Method ", m)
end

function add_method_trigger!(methodinvs, method::Method, reason::Symbol, mt_backedges, backedges, mt_cache, mt_disable)
    found = false
    for tree in methodinvs
        if tree.cause == method && tree.reason == reason
            join_invalidations!(tree.mt_backedges, mt_backedges)
            join_invalidations!(tree.backedges, backedges)
            append!(tree.mt_cache, mt_cache)
            append!(tree.mt_disable, mt_disable)
            found = true
            break
        end
    end
    found || push!(methodinvs, sort!(InvalidationTree(method, reason, mt_backedges, backedges, mt_cache, mt_disable)))
    return methodinvs
end

# for backedges
function join_invalidations!(list::AbstractVector{InstanceNode}, items::AbstractVector{InstanceNode}, depth=Int32(1))
    for node in items
        if node.depth == 0 || node.mi === dummyinstance
            node ∉ list && push!(list, node)
            continue
        end
        @assert node.depth == depth
        mi = node.mi
        found = false
        for parent in list
            mi2 = parent.mi
            if mi2 == mi
                join_invalidations!(parent.children, node.children, depth+Int32(1))
                found = true
                break
            end
        end
        if !found
            adjust_depth!(node, -depth+Int32(1))
            push!(list, node)
        end
    end
    return list
end

# for mt_backedges
function join_invalidations!(list::AbstractVector{<:Pair}, items::AbstractVector{<:Pair})
    for (key, root) in items
        found = false
        node, mi = isa(root, MethodInstance) ? (InstanceNode(root, 0), root) : (root, root.mi)
        for (key2, root2) in list
            key2 == key || continue
            mi2 = root2.mi
            if mi2 == mi
                # Find the first branch that isn't shared
                join_branches!(node, root2)
                found = true
                break
            end
        end
        found || push!(list, key => node)
    end
    return list
end

function join_branches!(to, from)
    for cfrom in from.children
        found = false
        for cto in to.children
            if cfrom.mi == cto.mi
                join_branches!(cto, cfrom)
                found = true
                break
            end
        end
        found || push!(to.children, cfrom)
    end
    return to
end

function checkreason(reason, loctag)
    if loctag == "jl_method_table_disable"
        @assert reason === nothing || reason === :deleting
        reason = :deleting
    elseif loctag == "jl_method_table_insert"
        @assert reason === nothing || reason === :inserting
        reason = :inserting
    elseif loctag == "jl_maybe_log_binding_invalidation"
        @assert reason === nothing || reason === :modifying
        reason = :modifying
    else
        error("unexpected reason ", loctag)
    end
    return reason
end

"""
    thinned = filtermod(module, trees::AbstractVector{InvalidationTree}; recursive=false)

Select just the cases of invalidating a method defined in `module`.

If `recursive` is false, only the roots of trees are examined (i.e., the proximal source of
the invalidation must be in `module`). If `recursive` is true, then `thinned` contains
all routes to a method in `module`.
"""
function filtermod(mod::Module, trees::AbstractVector{InvalidationTree}; kwargs...)
    # We don't just broadcast because we want to filter at all levels
    thinned = InvalidationTree[]
    for methinvs in trees
        _invs = filtermod(mod, methinvs; kwargs...)
        isempty(_invs) || push!(thinned, _invs)
    end
    return sort!(thinned; by=countchildren)
end

hasmod(mod::Module, node::InstanceNode) = hasmod(mod, MethodInstance(node))
hasmod(mod::Module, mi::MethodInstance) = mi.def.module === mod

function filtermod(mod::Module, methinvs::InvalidationTree; recursive::Bool=false)
    if recursive
        out = InvalidationTree(methinvs.cause, methinvs.reason)
        for (sig, node) in methinvs.mt_backedges
            newnode = filtermod(mod, node)
            if newnode !== nothing
                push!(out.mt_backedges, sig => newnode)
            end
        end
        for node in methinvs.backedges
            newnode = filtermod(mod, node)
            if newnode !== nothing
                push!(out.backedges, newnode)
            end
        end
        return out
    end
    mt_backedges = filter(pr->hasmod(mod, pr.second), methinvs.mt_backedges)
    backedges = filter(root->hasmod(mod, root), methinvs.backedges)
    return InvalidationTree(methinvs.cause, methinvs.reason, mt_backedges, backedges,
                               copy(methinvs.mt_cache), copy(methinvs.mt_disable))
end

function filterbranch(f, node::InstanceNode, storage=nothing)
    if !isempty(node.children)
        newchildren = InstanceNode[]
        for child in node.children
            newchild = filterbranch(f, child, storage)
            if newchild !== nothing
                push!(newchildren, newchild)
            end
        end
        if !isempty(newchildren)
            newnode = InstanceNode(node, newchildren)
            for child in newchildren
                child.parent = newnode
            end
            return newnode
        end
    end
    if f(node)
        storage !== nothing && push!(storage, convert(eltype(storage), node))
        return copybranch(node)
    end
    return nothing
end
function filterbranch(f, node::MethodInstance, storage=nothing)
    if f(node)
        storage !== nothing && push!(storage, convert(eltype(storage), node))
        return node
    end
    return nothing
end

filtermod(mod::Module, node::InstanceNode) = filterbranch(n -> hasmod(mod, n), node)

function filtermod(mod::Module, mi::MethodInstance)
    m = mi.def
    if isa(m, Method)
        return m.module == mod ? mi : nothing
    end
    return m == mod ? mi : nothing
end

"""
    methinvs = findcaller(method::Method, trees)

Find a path through `trees` that reaches `method`. Returns a single `InvalidationTree` object.

# Examples

Suppose you know that loading package `SomePkg` triggers invalidation of `f(data)`.
You can find the specific source of invalidation as follows:

```
f(data)                             # run once to force compilation
m = @which f(data)
using SnoopCompile
trees = invalidation_trees(@snoop_invalidations using SomePkg)
methinvs = findcaller(m, trees)
```

If you don't know which method to look for, but know some operation that has had added latency,
you can look for methods using `@snoopi`. For example, suppose that loading `SomePkg` makes the
next `using` statement slow. You can find the source of trouble with

```
julia> using SnoopCompile

julia> trees = invalidation_trees(@snoop_invalidations using SomePkg);

julia> tinf = @snoopi using SomePkg            # this second `using` will need to recompile code invalidated above
1-element Array{Tuple{Float64,Core.MethodInstance},1}:
 (0.08518409729003906, MethodInstance for require(::Module, ::Symbol))

julia> m = tinf[1][2].def
require(into::Module, mod::Symbol) in Base at loading.jl:887

julia> findcaller(m, trees)
inserting ==(x, y::SomeType) in SomeOtherPkg at /path/to/code:100 invalidated:
   backedges: 1: superseding ==(x, y) in Base at operators.jl:83 with MethodInstance for ==(::Symbol, ::Any) (16 children) more specific
```
"""
function findcaller(meth::Method, trees::AbstractVector{InvalidationTree})
    for methinvs in trees
        ret = findcaller(meth, methinvs)
        ret === nothing || return ret
    end
    return nothing
end

function findcaller(meth::Method, methinvs::InvalidationTree)
    function newtree(vectree)
        root0 = pop!(vectree)
        root = InstanceNode(root0.mi, root0.depth)
        return newtree!(root, vectree)
    end
    function newtree!(parent, vectree)
        isempty(vectree) && return getroot(parent)
        child = pop!(vectree)
        newchild = InstanceNode(child.mi, parent, child.depth)   # prune all branches except the one leading through child.mi
        return newtree!(newchild, vectree)
    end

    for (sig, node) in methinvs.mt_backedges
        ret = findcaller(meth, node)
        ret === nothing && continue
        return InvalidationTree(methinvs.cause, methinvs.reason, [Pair{Any,InstanceNode}(sig, newtree(ret))], InstanceNode[],
                                   copy(methinvs.mt_cache), copy(methinvs.mt_disable))
    end
    for node in methinvs.backedges
        ret = findcaller(meth, node)
        ret === nothing && continue
        return InvalidationTree(methinvs.cause, methinvs.reason, Pair{Any,InstanceNode}[], [newtree(ret)],
                                   copy(methinvs.mt_cache), copy(methinvs.mt_disable))
    end
    return nothing
end

function findcaller(meth::Method, node::InstanceNode)
    meth === node.mi.def && return [node]
    for child in node.children
        ret = findcaller(meth, child)
        if ret !== nothing
            push!(ret, node)
            return ret
        end
    end
    return nothing
end

findcaller(meth::Method, mi::MethodInstance) = mi.def == meth ? mi : nothing
