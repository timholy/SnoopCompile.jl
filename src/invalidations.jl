export uinvalidated, invalidation_trees, filtermod, findcaller

const have_verify_methods = Base.VERSION >= v"1.9.0-DEV.1512" || Base.VERSION >= v"1.8.4"

function from_corecompiler(mi::MethodInstance)
    fn = fullname(mi.def.module)
    length(fn) < 2 && return false
    fn[1] === :Core || return false
    return fn[2] === :Compiler
end

"""
    umis = uinvalidated(invlist)

Return the unique invalidated MethodInstances. `invlist` is obtained from [`SnoopCompileCore.@snoopr`](@ref).
This is similar to `filter`ing for `MethodInstance`s in `invlist`, except that it discards any tagged
`"invalidate_mt_cache"`. These can typically be ignored because they are nearly inconsequential:
they do not invalidate any compiled code, they only transiently affect an optimization of runtime dispatch.
"""
function uinvalidated(invlist; exclude_corecompiler::Bool=true)
    umis = Set{MethodInstance}()
    i, ilast = firstindex(invlist), lastindex(invlist)
    while i <= ilast
        item = invlist[i]
        if isa(item, Core.MethodInstance)
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
# - `methinvs::MethodInvalidations`: the set of invalidations that occur from inserting or deleting a method
# - `trees`: a list of `methinvs`

dummy() = nothing
dummy()
const dummyinstance = first(specializations(which(dummy, ())))

mutable struct InstanceNode
    mi::MethodInstance
    depth::Int32
    children::Vector{InstanceNode}
    parent::InstanceNode

    # Create a new tree. Creates the `root`, but returns the `leaf` holding `mi`.
    # `root == leaf` if `depth = 0`, otherwise parent "dummy" nodes are inserted until
    # the root is created at `depth` 0.
    function InstanceNode(mi::MethodInstance, depth)
        leaf = new(mi, depth, InstanceNode[])
        child = leaf
        while depth > 0
            depth -= 1
            parent = new(dummyinstance, depth, InstanceNode[])
            push!(parent.children, child)
            child.parent = parent
            child = parent
        end
        return leaf
    end
    InstanceNode(mi::MethodInstance, children::Vector{InstanceNode}) = return new(mi, 0, children)
    # Create child with a given `parent`. Checks that the depths are consistent.
    function InstanceNode(mi::MethodInstance, parent::InstanceNode, depth=parent.depth+Int32(1))
        depth !== nothing && @assert parent.depth + Int32(1) == depth
        child = new(mi, depth, InstanceNode[], parent)
        push!(parent.children, child)
        return child
    end
    # Creating a tree, starting with the leaves (omits `parent`)
    function InstanceNode(node::InstanceNode, newchildren::Vector{InstanceNode})
        return new(node.mi, node.depth, newchildren)
    end
end

Core.MethodInstance(node::InstanceNode) = node.mi
Base.convert(::Type{MethodInstance}, node::InstanceNode) = node.mi
AbstractTrees.children(node::InstanceNode) = node.children

function getroot(node::InstanceNode)
    while isdefined(node, :parent)
        node = node.parent
    end
    return node
end

function Base.any(f, node::InstanceNode)
    f(node) && return true
    return any(f, node.children)
end

# TODO: deprecate this in favor of `AbstractTrees.print_tree`, and limit it to one layer (e.g., like `:showchildren=>false`)
function Base.show(io::IO, node::InstanceNode; methods=false, maxdepth::Int=5, minchildren::Int=round(Int, sqrt(countchildren(node))))
    if get(io, :limit, false)
        print(io, node.mi, " at depth ", node.depth, " with ", countchildren(node), " children")
    else
        nc = map(countchildren, node.children)
        s = sum(nc) + length(node.children)
        indent = " "^Int(node.depth)
        print(io, indent, methods ? node.mi.def : node.mi)
        println(io, " (", s, " children)")
        if get(io, :showchildren, true)::Bool
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
end
Base.show(node::InstanceNode; kwargs...) = show(stdout, node; kwargs...)

function copybranch(node::InstanceNode)
    children = InstanceNode[copybranch(child) for child in node.children]
    newnode = InstanceNode(node, children)
    for child in children
        child.parent = newnode
    end
    return newnode
end

function countchildren(node::InstanceNode)
    n = length(node.children)
    for child in node.children
        n += countchildren(child)
    end
    return n
end

struct MethodInvalidations
    method::Method
    reason::Symbol   # :inserting or :deleting
    mt_backedges::Vector{Pair{Type,Union{InstanceNode,MethodInstance}}}   # sig=>root
    backedges::Vector{InstanceNode}
    mt_cache::Vector{MethodInstance}
    mt_disable::Vector{MethodInstance}
end
methinv_storage() = Pair{Type,InstanceNode}[], InstanceNode[], MethodInstance[], MethodInstance[]
function MethodInvalidations(method::Method, reason::Symbol)
    MethodInvalidations(method, reason, methinv_storage()...)
end

Base.isempty(methinvs::MethodInvalidations) = isempty(methinvs.mt_backedges) && isempty(methinvs.backedges)  # ignore mt_cache

function Base.:(==)(methinvs1::MethodInvalidations, methinvs2::MethodInvalidations)
    methinvs1.method == methinvs2.method || return false
    methinvs1.reason == methinvs2.reason || return false
    methinvs1.mt_backedges == methinvs2.mt_backedges || return false
    methinvs1.backedges == methinvs2.backedges || return false
    methinvs1.mt_cache == methinvs2.mt_cache || return false
    methinvs1.mt_disable == methinvs2.mt_disable || return false
    return true
end

countchildren(sigtree::Pair{<:Any,Union{InstanceNode,MethodInstance}}) = countchildren(sigtree.second)
countchildren(::MethodInstance) = 1

function countchildren(methinvs::MethodInvalidations)
    n = 0
    for list in (methinvs.mt_backedges, methinvs.backedges)
        for root in list
            n += countchildren(root)
        end
    end
    return n
end

function Base.sort!(methinvs::MethodInvalidations)
    sort!(methinvs.mt_backedges; by=countchildren)
    sort!(methinvs.backedges; by=countchildren)
    return methinvs
end

# We could use AbstractTrees here, but typically one is not interested in the full tree,
# just the top method and the number of children it has
function Base.show(io::IO, methinvs::MethodInvalidations)
    iscompact = get(io, :compact, false)::Bool

    print(io, methinvs.reason, " ")
    printstyled(io, methinvs.method, color = :light_magenta)
    println(io, " invalidated:")
    indent = iscompact ? "" : "   "
    if !isempty(methinvs.mt_backedges)
        print(io, indent, "mt_backedges: ")
        showlist(io, methinvs.mt_backedges, length(indent)+length("mt_backedges")+2)
    end
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
        sig = nothing
        if isa(root, Pair)
            print(io, "signature ")
            sig = root.first
            if isa(sig, MethodInstance)
                # "insert_backedges_callee"/"insert_backedges" (delayed) invalidations
                printstyled(io, try which(sig.specTypes) catch _ "(unavailable)" end, color = :light_cyan)
                print(io, " (formerly ", sig.def, ')')
            else
                # `sig` (immediate) invalidations
                printstyled(io, sig, color = :light_cyan)
            end
            print(io, " triggered ")
            sig = root.first
            root = root.second
        elseif isa(root, Tuple)
            printstyled(IOContext(io, :showchildren=>false), root[end-1], color = :light_yellow)
            print(io, " blocked ")
            printdata(io, root[end])
            root = nothing
        else
            print(io, "superseding ")
            printstyled(io, convert(MethodInstance, root).def , color = :light_cyan)
            print(io, " with ")
            sig = root.mi.def.sig
        end
        if root !== nothing
            printstyled(io, convert(MethodInstance, root), color = :light_yellow)
            print(io, " (", countchildren(root), " children)")
        end
        if iscompact
            i < n && print(io, ", ")
        else
            print(io, '\n')
            i < n && print(io, " "^indent)
        end
    end
end

if have_verify_methods
    new_backedge_table() = Dict{Union{Int32,MethodInstance},Union{Tuple{Any,Vector{Any}},InstanceNode}}()
else
    new_backedge_table() = Dict{Tuple{Int32,UInt64},Tuple{Any,Vector{Any}}}()
end

"""
    report_invalidations(
        io::IO = stdout;
        invalidations,
        n_rows::Int = 10,
        process_filename::Function = x -> x,
    )

Print a tabular summary of invalidations given:

 - `invalidations` the output of [`SnoopCompileCore.@snoopr`](@ref)

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
invalidations = SnoopCompileCore.@snoopr begin

    # load packages & define any additional methods

end;

using SnoopCompile
using PrettyTables # to load report_invalidations
report_invalidations(;invalidations)
```

Using `report_invalidations` requires that you first load the `PrettyTables.jl` package.
"""
function report_invalidations end

"""
    trees = invalidation_trees(list)

Parse `list`, as captured by [`SnoopCompileCore.@snoopr`](@ref), into a set of invalidation trees, where parents nodes
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
 inserting f(::AbstractFloat) in Main at REPL[36]:1 invalidated:
   mt_backedges: 1: signature Tuple{typeof(f),Any} triggered MethodInstance for applyf(::Array{Any,1}) (1 children) more specific
```

See the documentation for further details.
"""
function invalidation_trees(list; exclude_corecompiler::Bool=true)

    function handle_insert_backedges(list, i, callee)
        if have_verify_methods
            key, causes = list[i+=1], list[i+=1]
            backedge_table[key] = (callee, causes)
            return i
        end
        if Base.VERSION >= v"1.9.0-DEV.1432"
            key = (list[i+=1], list[i+=1])
            backedge_table[key] = (callee, list[i+=1])
            return i
        end

        ncovered = 0
        callees = Any[callee]
        i0 = i
        while length(list) >= i+2 && list[i+2] == "insert_backedges_callee"
            push!(callees, list[i+1])
            i += 2
        end
        callers = MethodInstance[]
        while length(list) >= i+2 && list[i+2] == "insert_backedges"
            push!(callers, list[i+1])
            i += 2
            ncovered += 1
        end
        push!(delayed, callees => callers)
        i > i0 && @assert ncovered > 0
        return i
    end

    methodinvs = MethodInvalidations[]
    delayed = Pair{Vector{Any},Vector{MethodInstance}}[]   # from "insert_backedges" invalidations
    leaf = nothing
    mt_backedges, backedges, mt_cache, mt_disable = methinv_storage()
    reason = nothing
    backedge_table = new_backedge_table()
    inserted_backedges = false
    i = 0
    while i < length(list)
        item = list[i+=1]
        if isa(item, MethodInstance)
            mi = item
            item = list[i+=1]
            if isa(item, Int32)
                depth = item
                if leaf === nothing
                    leaf = InstanceNode(mi, depth)
                else
                    # Recurse back up the tree until we find the right parent
                    node = leaf
                    while node.depth >= depth
                        node = node.parent
                    end
                    leaf = InstanceNode(mi, node, depth)
                end
            elseif isa(item, String)
                loctag = item
                if Base.VERSION >= v"1.9.0-DEV.1512" && loctag ∉ ("insert_backedges_callee", "verify_methods") && inserted_backedges
                    # The integer index resets between packages, clear all with integer keys
                    ikeys = collect(Iterators.filter(x -> isa(x, Integer), keys(backedge_table)))
                    for key in ikeys
                        delete!(backedge_table, key)
                    end
                    inserted_backedges = false
                end
                if loctag == "invalidate_mt_cache"
                    push!(mt_cache, mi)
                    leaf = nothing
                elseif loctag == "jl_method_table_insert"
                    if leaf !== nothing    # we logged without actually invalidating anything (issue #354)
                        root = getroot(leaf)
                        root.mi = mi
                        if !exclude_corecompiler || !from_corecompiler(mi)
                            push!(backedges, root)
                        end
                        leaf = nothing
                    end
                elseif loctag == "jl_insert_method_instance"
                    @assert leaf !== nothing
                    root = getroot(leaf)
                    root = only(root.children)
                    push!(mt_backedges, mi=>root)
                elseif loctag == "jl_insert_method_instance caller"
                    if leaf === nothing
                        leaf = InstanceNode(mi, 1)
                    else
                        push!(leaf.children, mi)
                    end
                elseif loctag == "jl_method_table_disable"
                    if leaf === nothing
                        push!(mt_disable, mi)
                    else
                        root = getroot(leaf)
                        root.mi = mi
                        if !exclude_corecompiler || !from_corecompiler(mi)
                            push!(backedges, root)
                        end
                        leaf = nothing
                    end
                elseif loctag == "insert_backedges_callee"
                    i = handle_insert_backedges(list, i, mi)
                    inserted_backedges = true
                elseif loctag == "verify_methods"
                    next = list[i+=1]
                    if isa(next, Integer)
                        ret = get(backedge_table, next, nothing)
                        ret === nothing && (@warn "$next not found in `backedge_table`"; continue)
                        trig, causes = ret
                        if isa(trig, MethodInstance)
                            newnode = InstanceNode(trig, 1)
                            push!(backedges, newnode)
                            newchild = InstanceNode(mi, 2)
                            push!(newnode.children, newchild)
                            backedge_table[trig] = newnode
                            backedge_table[mi] = newchild
                        else
                            newnode = InstanceNode(mi, 1)
                            push!(mt_backedges, trig => newnode)
                            backedge_table[mi] = newnode
                        end
                        for cause in causes
                            add_method_trigger!(methodinvs, cause, :inserting, mt_backedges, backedges, mt_cache, mt_disable)
                        end
                        mt_backedges, backedges, mt_cache, mt_disable = methinv_storage()
                        leaf = nothing
                        reason = nothing
                    else
                        @assert isa(next, MethodInstance) "unexpected logging format"
                        parent = get(backedge_table, next, nothing)
                        parent === nothing && (@warn "$next not found in `backedge_table`"; continue)
                        found = false
                        for child in parent.children
                            if child.mi == mi
                                found = true
                                break
                            end
                        end
                        if !found
                            newnode = InstanceNode(mi, parent)
                            if !haskey(backedge_table, mi)
                                backedge_table[mi] = newnode
                            end
                        end
                    end
                elseif loctag == "insert_backedges"
                    if Base.VERSION >= v"1.9.0-DEV.1432"
                        key = (list[i+=1], list[i+=1])
                        trig, causes = backedge_table[key]
                        if leaf !== nothing
                            root = getroot(leaf)
                            root.mi = mi
                            if trig isa MethodInstance
                                oldroot = root
                                root = InstanceNode(trig, [root])
                                oldroot.parent = root
                                push!(backedges, root)
                            else
                                push!(mt_backedges, trig=>root)
                            end
                        end
                        for cause in causes
                            add_method_trigger!(methodinvs, cause, :inserting, mt_backedges, backedges, mt_cache, mt_disable)
                        end
                        mt_backedges, backedges, mt_cache, mt_disable = methinv_storage()
                        leaf = nothing
                        reason = nothing
                    else
                        # pre Julia 1.8
                        Base.VERSION < v"1.8.0-DEV.368" || error("unexpected failure at ", i)
                        @assert leaf === nothing
                    end
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
                add_method_trigger!(methodinvs, method, reason, mt_backedges, backedges, mt_cache, mt_disable)
                mt_backedges, backedges, mt_cache, mt_disable = methinv_storage()
                leaf = nothing
                reason = nothing
            else
                error("unexpected item ", item, " at ", i)
            end
        elseif isa(item, String)
            # This shouldn't happen
            reason = checkreason(reason, item)
            push!(backedges, getroot(leaf))
            leaf = nothing
            reason = nothing
        elseif isa(item, Type)
            if length(list) > i && list[i+1] == "insert_backedges_callee"
                i = handle_insert_backedges(list, i+1, item)
            else
                root = getroot(leaf)
                if !exclude_corecompiler || !from_corecompiler(root.mi)
                    push!(mt_backedges, item=>root)
                end
                leaf = nothing
            end
        elseif isa(item, Core.TypeMapEntry) && list[i+1] == "invalidate_mt_cache"
            i += 1
        else
            error("unexpected item ", item, " at ", i)
        end
    end
    @assert all(isempty, Any[mt_backedges, backedges, #= mt_cache, =# mt_disable])
    # Handle the delayed invalidations
    callee2idx = Dict{Method,Int}()
    for (i, methinvs) in enumerate(methodinvs)
        for (sig, root) in methinvs.mt_backedges
            for node in PreOrderDFS(root)
                callee2idx[MethodInstance(node).def] = i
            end
        end
        for root in methinvs.backedges
            for node in PreOrderDFS(root)
                callee2idx[MethodInstance(node).def] = i
            end
        end
    end
    solved = Int[]
    for (i, (callees, callers)) in enumerate(delayed)
        for callee in callees
            if isa(callee, MethodInstance)
                idx = get(callee2idx, callee.def, nothing)
                if idx !== nothing
                    for caller in callers
                        join_invalidations!(methodinvs[idx].mt_backedges, [callee => caller])
                    end
                    push!(solved, i)
                    break
                end
            end
        end
    end
    deleteat!(delayed, solved)
    if !isempty(delayed)
        @warn "Could not attribute the following delayed invalidations:"
        for (callees, callers) in delayed
            @assert !isempty(callees)   # this shouldn't ever happen
            printstyled(length(callees) == 1 ? callees[1] : callees; color = :light_cyan)
            print(" invalidated ")
            printstyled(length(callers) == 1 ? callers[1] : callers; color = :light_yellow)
            println()
        end
    end
    return sort!(methodinvs; by=countchildren)
end

function add_method_trigger!(methodinvs, method::Method, reason::Symbol, mt_backedges, backedges, mt_cache, mt_disable)
    found = false
    for tree in methodinvs
        if tree.method == method && tree.reason == reason
            join_invalidations!(tree.mt_backedges, mt_backedges)
            append!(tree.backedges, backedges)
            append!(tree.mt_cache, mt_cache)
            append!(tree.mt_disable, mt_disable)
            found = true
            break
        end
    end
    found || push!(methodinvs, sort!(MethodInvalidations(method, reason, mt_backedges, backedges, mt_cache, mt_disable)))
    return methodinvs
end

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
    else
        error("unexpected reason ", loctag)
    end
    return reason
end

"""
    thinned = filtermod(module, trees::AbstractVector{MethodInvalidations}; recursive=false)

Select just the cases of invalidating a method defined in `module`.

If `recursive` is false, only the roots of trees are examined (i.e., the proximal source of
the invalidation must be in `module`). If `recursive` is true, then `thinned` contains
all routes to a method in `module`.
"""
function filtermod(mod::Module, trees::AbstractVector{MethodInvalidations}; kwargs...)
    # We don't just broadcast because we want to filter at all levels
    thinned = MethodInvalidations[]
    for methinvs in trees
        _invs = filtermod(mod, methinvs; kwargs...)
        isempty(_invs) || push!(thinned, _invs)
    end
    return sort!(thinned; by=countchildren)
end

hasmod(mod::Module, node::InstanceNode) = hasmod(mod, MethodInstance(node))
hasmod(mod::Module, mi::MethodInstance) = mi.def.module === mod

function filtermod(mod::Module, methinvs::MethodInvalidations; recursive::Bool=false)
    if recursive
        out = MethodInvalidations(methinvs.method, methinvs.reason)
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
    return MethodInvalidations(methinvs.method, methinvs.reason, mt_backedges, backedges,
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

Find a path through `trees` that reaches `method`. Returns a single `MethodInvalidations` object.

# Examples

Suppose you know that loading package `SomePkg` triggers invalidation of `f(data)`.
You can find the specific source of invalidation as follows:

```
f(data)                             # run once to force compilation
m = @which f(data)
using SnoopCompile
trees = invalidation_trees(@snoopr using SomePkg)
methinvs = findcaller(m, trees)
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
inserting ==(x, y::SomeType) in SomeOtherPkg at /path/to/code:100 invalidated:
   backedges: 1: superseding ==(x, y) in Base at operators.jl:83 with MethodInstance for ==(::Symbol, ::Any) (16 children) more specific
```
"""
function findcaller(meth::Method, trees::AbstractVector{MethodInvalidations})
    for methinvs in trees
        ret = findcaller(meth, methinvs)
        ret === nothing || return ret
    end
    return nothing
end

function findcaller(meth::Method, methinvs::MethodInvalidations)
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
        return MethodInvalidations(methinvs.method, methinvs.reason, [Pair{Any,InstanceNode}(sig, newtree(ret))], InstanceNode[],
                                   copy(methinvs.mt_cache), copy(methinvs.mt_disable))
    end
    for node in methinvs.backedges
        ret = findcaller(meth, node)
        ret === nothing && continue
        return MethodInvalidations(methinvs.method, methinvs.reason, Pair{Any,InstanceNode}[], [newtree(ret)],
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
