using Cthulhu

export uinvalidated, invalidation_trees, filtermod, findcaller, ascend

"""
   umis = uinvalidated(invlist)

Return the unique invalidated MethodInstances. `invlist` is obtained from [`SnoopCompileCore.@snoopr`](@ref).
This is similar to `filter`ing for `MethodInstance`s in `invlist`, except that it discards any tagged
`"invalidate_mt_cache"`. These can typically be ignored because they are nearly inconsequential:
they do not invalidate any compiled code, they only transiently affect an optimization of runtime dispatch.
"""
function uinvalidated(invlist)
    umis = Set{MethodInstance}()
    for (i, item) in enumerate(invlist)
        if isa(item, Core.MethodInstance)
            if invlist[i+1] != "invalidate_mt_cache"
                push!(umis, item)
            end
        end
    end
    return umis
end

# Variable names:
# - `node`, `root`, `leaf`, `parent`, `child`: all `InstanceNode`s, a.k.a. nodes in a MethodInstance tree
# - `methinvs::MethodInvalidations`: the set of invalidations that occur from inserting or deleting a method
# - `trees`: a list of `methinvs`

dummy() = nothing
dummy()
const dummyinstance = which(dummy, ()).specializations[1]

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
    # Create child with a given `parent`. Checks that the depths are consistent.
    function InstanceNode(mi::MethodInstance, parent::InstanceNode, depth)
        @assert parent.depth + Int32(1) == depth
        child = new(mi, depth, InstanceNode[], parent)
        push!(parent.children, child)
        return child
    end
end

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

function Base.show(io::IO, node::InstanceNode; methods=false, maxdepth::Int=5, minchildren::Int=round(Int, sqrt(countchildren(node))))
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
Base.show(node::InstanceNode; kwargs...) = show(stdout, node; kwargs...)

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
    mt_backedges::Vector{Pair{Any,InstanceNode}}   # sig=>root
    backedges::Vector{InstanceNode}
    mt_cache::Vector{MethodInstance}
end
methinv_storage() = Pair{Any,InstanceNode}[], InstanceNode[], MethodInstance[]
function MethodInvalidations(method::Method, reason::Symbol)
    MethodInvalidations(method, reason, methinv_storage()...)
end

Base.isempty(methinvs::MethodInvalidations) = isempty(methinvs.mt_backedges) && isempty(methinvs.backedges)  # ignore mt_cache

countchildren(sigtree::Pair{<:Any,InstanceNode}) = countchildren(sigtree.second)

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
    method = methinvs.method

    function showlist(io, treelist, indent=0)
        nc = map(countchildren, treelist)
        n = length(treelist)
        nd = ndigits(n)
        for i = 1:n
            print(io, lpad(i, nd), ": ")
            root = treelist[i]
            sig = nothing
            if isa(root, Pair)
                print(io, "signature ")
                printstyled(io, root.first, color = :light_cyan)
                print(io, " triggered ")
                sig = root.first
                root = root.second
            else
                print(io, "superseding ")
                printstyled(io, root.mi.def , color = :light_cyan)
                print(io, " with ")
                sig = root.mi.def.sig
            end
            printstyled(io, root.mi, color = :light_yellow)
            print(io, " (", countchildren(root), " children)")
            # if sig !== nothing
            #     ms1, ms2 = method.sig <: sig, sig <: method.sig
            #     diagnosis = if ms1 && !ms2
            #         "more specific"
            #     elseif ms2 && !ms1
            #         "less specific"
            #     elseif ms1 && ms1
            #         "equal specificity"
            #     else
            #         "ambiguous"
            #     end
            #     printstyled(io, ' ', diagnosis, color=:red)
            # end
            if iscompact
                i < n && print(io, ", ")
            else
                print(io, '\n')
                i < n && print(io, " "^indent)
            end
        end
    end
    print(io, methinvs.reason, " ")
    printstyled(io, methinvs.method, color = :light_magenta)
    println(io, " invalidated:")
    indent = iscompact ? "" : "   "
    for fn in (:mt_backedges, :backedges)
        val = getfield(methinvs, fn)
        if !isempty(val)
            print(io, indent, fn, ": ")
            showlist(io, val, length(indent)+length(String(fn))+2)
        end
        iscompact && print(io, "; ")
    end
    if !isempty(methinvs.mt_cache)
        println(io, indent, length(methinvs.mt_cache), " mt_cache")
    end
    iscompact && print(io, ';')
end

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
function invalidation_trees(list)
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

    methodinvs = MethodInvalidations[]
    leaf = nothing
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
                if loctag == "invalidate_mt_cache"
                    push!(mt_cache, mi)
                    leaf = nothing
                elseif loctag == "jl_method_table_insert"
                    root = getroot(leaf)
                    root.mi = mi
                    push!(backedges, root)
                    leaf = nothing
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
            push!(mt_backedges, item=>getroot(leaf))
            leaf = nothing
        elseif isa(item, Core.TypeMapEntry) && list[i+1] == "invalidate_mt_cache"
            i += 1
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
    for methinvs in trees
        _invs = filtermod(mod, methinvs)
        isempty(_invs) || push!(thinned, _invs)
    end
    return sort!(thinned; by=countchildren)
end

function filtermod(mod::Module, methinvs::MethodInvalidations)
    hasmod(mod, node::InstanceNode) = node.mi.def.module === mod

    mt_backedges = filter(pr->hasmod(mod, pr.second), methinvs.mt_backedges)
    backedges = filter(root->hasmod(mod, root), methinvs.backedges)
    return MethodInvalidations(methinvs.method, methinvs.reason, mt_backedges, backedges, copy(methinvs.mt_cache))
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
        return MethodInvalidations(methinvs.method, methinvs.reason, [Pair{Any,InstanceNode}(sig, newtree(ret))], InstanceNode[], copy(methinvs.mt_cache))
    end
    for node in methinvs.backedges
        ret = findcaller(meth, node)
        ret === nothing && continue
        return MethodInvalidations(methinvs.method, methinvs.reason, Pair{Any,InstanceNode}[], [newtree(ret)], copy(methinvs.mt_cache))
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

# Cthulhu integration

Cthulhu.backedges(node::InstanceNode) = sort(node.children; by=countchildren, rev=true)
Cthulhu.method(node::InstanceNode) = Cthulhu.method(node.mi)
Cthulhu.specTypes(node::InstanceNode) = Cthulhu.specTypes(node.mi)
Cthulhu.instance(node::InstanceNode) = node.mi
