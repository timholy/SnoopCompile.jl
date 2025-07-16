module PkgC
Base.Experimental.@max_methods 4

nbits(::Int8) = 8
nbits(::Int16) = 16
nbits(::Integer) = -1  # fallback method

function lacks_methods end

const someconst = 1

struct MyType
    x::Int
end

end # module PkgC
