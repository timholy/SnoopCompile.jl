module CthulhuExt
    import Cthulhu
    using Core: MethodInstance
    using SnoopCompile: InstanceNode, TriggerNode, Suggested, InferenceTrigger, countchildren


    # Originally from invalidations.jl
    Cthulhu.backedges(node::InstanceNode) = sort(node.children; by=countchildren, rev=true)
    Cthulhu.method(node::InstanceNode) = Cthulhu.method(node.mi)
    Cthulhu.specTypes(node::InstanceNode) = Cthulhu.specTypes(node.mi)
    Cthulhu.instance(node::InstanceNode) = node.mi

    # Originally from parcel_snoopi_deep.jl

    Cthulhu.descend(itrig::InferenceTrigger; kwargs...) = descend(callerinstance(itrig); kwargs...)
    Cthulhu.instance(itrig::InferenceTrigger) = MethodInstance(itrig.node)
    Cthulhu.method(itrig::InferenceTrigger) = Method(itrig.node)
    Cthulhu.specTypes(itrig::InferenceTrigger) = Cthulhu.specTypes(Cthulhu.instance(itrig))
    Cthulhu.backedges(itrig::InferenceTrigger) = (itrig.callerframes,)
    Cthulhu.nextnode(itrig::InferenceTrigger, edge) = (ret = callingframe(itrig); return isempty(ret.callerframes) ? nothing : ret)

    Cthulhu.ascend(node::TriggerNode) = ascend(node.itrig)
    Cthulhu.ascend(s::Suggested) = ascend(s.itrig)
end
