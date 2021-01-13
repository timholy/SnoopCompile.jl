# dummy module for testing assignment in parcel
module A
    module B
        module C
        struct CT
            x::Int
        end
        end
        module D
        end
    end
    f(a) = 1
    myjoin(arg::String, args::String...) = arg * " " * join(args, ' ')
end
