module CthulhuExt
    import Cthulhu
    using Core: MethodInstance
    using SnoopCompile: InstanceNode, TriggerNode, Suggested, InferenceTrigger, countchildren, callingframe, callerinstance


    # Originally from invalidations.jl
    Cthulhu.backedges(node::InstanceNode) = sort(node.children; by=countchildren, rev=true)
    Cthulhu.method(node::InstanceNode) = Cthulhu.method(node.mi)
    Cthulhu.specTypes(node::InstanceNode) = Cthulhu.specTypes(node.mi)
    Cthulhu.instance(node::InstanceNode) = node.mi

    # Originally from parcel_snoop_inference.jl

    Cthulhu.descend(itrig::InferenceTrigger; kwargs...) = Cthulhu.descend(callerinstance(itrig); kwargs...)
    Cthulhu.instance(itrig::InferenceTrigger) = MethodInstance(itrig.node)
    Cthulhu.method(itrig::InferenceTrigger) = Method(itrig.node)
    Cthulhu.specTypes(itrig::InferenceTrigger) = Cthulhu.specTypes(Cthulhu.instance(itrig))
    Cthulhu.backedges(itrig::InferenceTrigger) = (itrig.callerframes,)
    Cthulhu.nextnode(itrig::InferenceTrigger, edge) = (ret = callingframe(itrig); return isempty(ret.callerframes) ? nothing : ret)

    Cthulhu.ascend(node::TriggerNode) = Cthulhu.ascend(node.itrig)
    Cthulhu.ascend(s::Suggested) = Cthulhu.ascend(s.itrig)
end
