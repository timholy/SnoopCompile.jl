# Combining invalidation and snoopi_deep data

struct StaleTree
    method::Method
    reason::Symbol   # :inserting or :deleting
    mt_backedges::Vector{Tuple{Any,Union{InstanceNode,MethodInstance},Vector{InferenceTimingNode}}}   # sig=>root
    backedges::Vector{Tuple{InstanceNode,Vector{InferenceTimingNode}}}
end
StaleTree(method::Method, reason) = StaleTree(method, reason, staletree_storage()...)

staletree_storage() = (
    Tuple{Any,Union{InstanceNode,MethodInstance},Vector{InferenceTimingNode}}[],
    Tuple{InstanceNode,Vector{InferenceTimingNode}}[])

function Base.show(io::IO, tree::StaleTree)
    iscompact = get(io, :compact, false)::Bool

    print(io, tree.reason, " ")
    printstyled(io, tree.method, color = :light_magenta)
    println(io, " invalidated:")
    indent = iscompact ? "" : "   "

    if !isempty(tree.mt_backedges)
        print(io, indent, "mt_backedges: ")
        showlist(io, tree.mt_backedges, length(indent)+length("mt_backedges")+2)
    end
    if !isempty(tree.backedges)
        print(io, indent, "backedges: ")
        showlist(io, tree.backedges, length(indent)+length("backedges")+2)
    end
    iscompact && print(io, ';')
end

function printdata(io, tnodes::AbstractVector{InferenceTimingNode})
    if length(tnodes) == 1
        print(io, tnodes[1])
    else
        print(io, sum(inclusive, tnodes), " inclusive time for $(length(tnodes)) nodes")
    end
end


"""
    staletrees = precompile_blockers(invalidations, tinf::InferenceTimingNode)

Select just those invalidations that contribute to "stale nodes" in `tinf`, and link them together.
This can allow one to identify specific blockers of precompilation for particular MethodInstances.

# Example

```julia
using SnoopCompileCore
invalidations = @snoopr using PkgA, PkgB;
using SnoopCompile
trees = invalidation_trees(invalidations)
tinf = @snoopi_deep begin
    some_workload()
end
staletrees = precompile_blockers(trees, tinf)
```
"""
function precompile_blockers(trees::Vector{MethodInvalidations}, tinf::InferenceTimingNode; kwargs...)
    sig2node = nodedict!(IdDict{Type,InferenceTimingNode}(), tinf)
    snodes = stalenodes(tinf; kwargs...)
    mi2stalenode = Dict(MethodInstance(node) => i for (i, node) in enumerate(snodes))
    # Prepare "thinned trees" focusing just on those invalidations that blocked precompilation
    staletrees = StaleTree[]
    for tree in trees
        mt_backedges, backedges = staletree_storage()
        for (sig, root) in tree.mt_backedges
            triggers = Set{MethodInstance}()
            thinned = filterbranch(node -> haskey(mi2stalenode, convert(MethodInstance, node)), root, triggers)
            if thinned !== nothing
                push!(mt_backedges, (sig, thinned, [snodes[mi2stalenode[mi]] for mi in triggers]))
            end
        end
        for root in tree.backedges
            triggers = Set{MethodInstance}()
            thinned = filterbranch(node -> haskey(mi2stalenode, convert(MethodInstance, node)), root, triggers)
            if thinned !== nothing
                push!(backedges, (thinned, [snodes[mi2stalenode[mi]] for mi in triggers]))
            end
        end
        if !isempty(mt_backedges) || !isempty(backedges)
            sort!(mt_backedges; by=suminclusive)
            sort!(backedges; by=suminclusive)
            push!(staletrees, StaleTree(tree.method, tree.reason, mt_backedges, backedges))
        end
    end
    sort!(staletrees; by=inclusive)
    return staletrees
end

precompile_blockers(invalidations, tinf::InferenceTimingNode; kwargs...) =
    precompile_blockers(invalidation_trees(invalidations)::Vector{MethodInvalidations}, tinf; kwargs...)


function nodedict!(d, tinf::InferenceTimingNode)
    for child in tinf.children
        sig = MethodInstance(child).specTypes
        oldinf = get(d, sig, nothing)
        if oldinf === nothing || inclusive(child) > inclusive(oldinf)
            d[sig] = child
        end
        nodedict!(d, child)
    end
    return d
end

suminclusive(t::Tuple) = sum(inclusive, last(t))
SnoopCompileCore.inclusive(tree::StaleTree) =
    sum(suminclusive, tree.mt_backedges; init=0.0) +
    sum(suminclusive, tree.backedges; init=0.0)
