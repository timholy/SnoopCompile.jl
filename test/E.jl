# dummy module for testing assignment in parcel
module E
    struct ET
        x::Int
    end
    # This is written elaborately to defeat inference
    function hasfoo(list)
        hf = false
        hf = map(list) do item
            if isa(item, AbstractString)
                (str->occursin("foo", str))(item)
            else
                false
            end
        end
        return any(hf)
    end
    @generated function Egen(x::T) where T
        Tbigger = T == Float32 ? Float64 : BigFloat
        :(convert($Tbigger, x))
    end
end
