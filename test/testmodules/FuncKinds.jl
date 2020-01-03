module FuncKinds

# Many of these are written elaborately to defeat inference

function hasfoo(list)   # a test for anonymous functions
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

## A test for keyword functions
const randnums = Any[1, 1.0, UInt(14), 2.0f0]

@noinline returnsrandom() = randnums[rand(1:length(randnums))]

@noinline function haskw(x, y; a="hello", b=1, c=returnsrandom())
    if isa(b, Integer)
        return cos(rand()) + c + x + y
    elseif isa(b, AbstractFloat)
        s = 0.0
        for i = 1:rand(1:10)
            s += log(rand())
        end
        return s + c + x + y
    end
    return "string"
end

function callhaskw()
    ret = Any[]
    for i = 1:5
        push!(ret, haskw(returnsrandom(), returnsrandom()))
    end
    push!(ret, haskw(returnsrandom(), returnsrandom(); b = 2.0))
    return ret
end

@generated function gen(x::T) where T
    Tbigger = T == Float32 ? Float64 : BigFloat
    :(convert($Tbigger, x))
end

function gen2(x::Int, y)
    if @generated
        return y <: Integer ? :(x*y) : :(x+y)
    else
        return 2x+3y
    end
end

function hasinner(x, y)
    inner(z) = 2z

    s = 0
    for i = 1:10
        s += inner(returnsrandom())
    end
    return s
end

# Two kwarg generated functions; one will be called from the no-kw call, the other from a kwcall
@generated function genkw1(; b=2)
    :(string(typeof($b)))
end
@generated function genkw2(; b=2)
    :(string(typeof($b)))
end

# Function styles from JuliaInterpreter
f1(x::Int) = 1
f1(x) = 2
# where signatures
f2(x::T) where T = -1
f2(x::T) where T<:Integer = T
f2(x::T) where Unsigned<:T<:Real = 0
f2(x::V) where V<:SubArray{T} where T = 2
f2(x::V) where V<:Array{T,N} where {T,N} = 3
f2(x::V) where V<:Base.ReshapedArray{T,N} where T where N = 4
# Varargs
f3(x::Int, y...) = 1
f3(x::Int, y::Symbol...) = 2
f3(x::T, y::U...) where {T<:Integer,U} = U
f3(x::Array{Float64,K}, y::Vararg{Symbol,K}) where K = K
# Default args
f4(x, y::Int=0) = 2
f4(x::UInt, y="hello", z::Int=0) = 3
f4(x::Array{Float64,K}, y::Int=0) where K = K
# Keyword args
f5(x::Int8; y=0) = y
f5(x::Int16; y::Int=0) = 2
f5(x::Int32; y="hello", z::Int=0) = 3
f5(x::Int64;) = 4
f5(x::Array{Float64,K}; y::Int=0) where K = K
# Default and keyword args
f6(x, y="hello"; z::Int=0) = 1

end
