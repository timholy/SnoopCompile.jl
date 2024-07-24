"""
OptimizeMeFixed is the "improved" version of OptimizeMe. See the file in this same directory for details.
"""
module OptimizeMeFixed

using PrecompileTools

struct Container{T}
    value::T
end
Base.show(io::IO, c::Container) = print(io, "Container(", c.value, ")")

function lotsa_containers(io::IO)
    list = [1, 0x01, 0xffff, 2.0f0, 'a', [0], ("key", 42)]
    cs = Container{Any}.(list)
    println(io, "lotsa containers:")
    show(io, MIME("text/plain"), cs)
end

howbig(str::AbstractString) = length(str)
howbig(x::Char) = 1
howbig(x::Unsigned) = x
howbig(x::Real) = abs(x)

function abmult(r::Int, ys)
    if r < 0
        r = -r
    end
    let r = r    # Julia #15276
        return map(x -> howbig(r * x), ys)
    end
end

function main()
    lotsa_containers(stdout)
    return abmult(rand(-5:5), rand(3))
end


@compile_workload begin
    lotsa_containers(devnull)  # use `devnull` to suppress output
    abmult(rand(-5:5), rand(3))
end
# since `devnull` is not a `Base.TTY`--the standard type of `stdout`--let's also
# use an explicit `precompile` directive. (Note this does not trigger any visible output).
# This doesn't "follow" runtime dispatch but at least it precompiles the entry point.
precompile(lotsa_containers, (Base.TTY,))

end
