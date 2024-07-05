using SnoopCompile
using SnoopCompile: countchildren

function hastv(typ)
    isa(typ, UnionAll) && return true
    if isa(typ, DataType)
        for p in typ.parameters
            hastv(p) && return true
        end
    end
    return false
end

trees = invalidation_trees(@snoop_invalidations using Revise)

function summary(trees)
    npartial = ngreater = nlesser = nambig = nequal = 0
    for methinvs in trees
        method = methinvs.method
        for fn in (:mt_backedges, :backedges)
            list = getfield(methinvs, fn)
            for item in list
                sig = nothing
                if isa(item, Pair)
                    sig = item.first
                    root = item.second
                else
                    sig = item.mi.def.sig
                    root = item
                end
                # if hastv(sig)
                #     npartial += countchildren(invtree)
                # else
                    ms1, ms2 = method.sig <: sig, sig <: method.sig
                    if ms1 && !ms2
                        ngreater += countchildren(root)
                    elseif ms2 && !ms1
                        nlesser += countchildren(root)
                    elseif ms1 && ms2
                        nequal += countchildren(root)
                    else
                        # if hastv(sig)
                        #     npartial += countchildren(root)
                        # else
                            nambig += countchildren(root)
                        # end
                    end
                # end
            end
        end
    end
    @assert nequal == 0
    println("$ngreater | $nlesser | $nambig |") # $npartial |")
end

summary(trees)
