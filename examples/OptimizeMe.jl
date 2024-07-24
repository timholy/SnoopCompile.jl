"""
OptimizeMe is a module used to demonstrate how to make code more precompilable
and more resistant to invalidation. It has deliberate weaknesses in its design,
and the analysis and resolution of these weaknesses via `@snoop_inference` is
discussed in the documentation.
"""
module OptimizeMe

struct Container{T}
    value::T
end

function lotsa_containers()
    list = [1, 0x01, 0xffff, 2.0f0, 'a', [0], ("key", 42)]
    cs = Container.(list)
    println("lotsa containers:")
    display(cs)
end

howbig(str::AbstractString) = length(str)
howbig(x::Char) = 1
howbig(x::Unsigned) = x
howbig(x::Real) = abs(x)

function abmult(r::Int, ys)
    if r < 0
        r = -r
    end
    return map(x -> howbig(r * x), ys)
end

function main()
    lotsa_containers()
    return abmult(rand(-5:5), rand(3))
end

end
